import 'dart:convert';

import 'package:saklaz_core/saklaz_core.dart';

import 'http_transport.dart';
import 'llm.dart';

/// Bulut sağlayıcıları. HEPSİ varsayılan olarak PASİFTİR; ücretler kullanıcıya aittir.
enum ProviderKind {
  openai('OpenAI', 'https://api.openai.com/v1', ''),
  deepseek('DeepSeek', 'https://api.deepseek.com', 'deepseek-chat'),
  custom('Özel (OpenAI uyumlu)', '', ''),
  gateway('SAKLAZ Gateway', '', '');

  const ProviderKind(this.label, this.defaultBaseUrl, this.defaultModel);
  final String label;
  final String defaultBaseUrl;
  final String defaultModel;

  /// API anahtarının güvenli depodaki adı.
  String get secretName => 'provider_${name}_key';
}

class ProviderSettings {
  const ProviderSettings({required this.kind, this.enabled = false, this.baseUrl = '', this.model = ''});
  final ProviderKind kind;
  final bool enabled;
  final String baseUrl;
  final String model;

  String get effectiveBaseUrl => (baseUrl.trim().isEmpty ? kind.defaultBaseUrl : baseUrl.trim()).replaceAll(RegExp(r'/+$'), '');
  String get effectiveModel => model.trim().isEmpty ? kind.defaultModel : model.trim();

  ProviderSettings copyWith({bool? enabled, String? baseUrl, String? model}) => ProviderSettings(
        kind: kind,
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
      );

  Map<String, Object?> toJson() => {'enabled': enabled, 'baseUrl': baseUrl, 'model': model};

  static ProviderSettings fromJson(ProviderKind kind, Map<String, Object?> j) => ProviderSettings(
        kind: kind,
        enabled: j['enabled'] == true,
        baseUrl: (j['baseUrl'] as String?) ?? '',
        model: (j['model'] as String?) ?? '',
      );
}

Failure _httpFailure(int status, String body) {
  String? detail;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['error'] is Map) detail = ((j['error'] as Map)['message'] as String?)?.trim();
  } on FormatException {
    // JSON değil
  }
  final suffix = detail == null || detail.isEmpty ? '' : ' (${detail.length > 120 ? '${detail.substring(0, 120)}…' : detail})';
  return switch (status) {
    401 || 403 => Failure('auth', 'API anahtarı reddedildi.$suffix'),
    402 => Failure('budget', 'Hesap bakiyesi yetersiz (ücretler sağlayıcıya ait).$suffix'),
    404 => Failure('model', 'Model veya adres bulunamadı.$suffix'),
    429 => Failure('rate-limit', 'Sağlayıcı istek sınırı veya kota doldu.$suffix'),
    >= 500 => Failure('upstream', 'Sağlayıcı şu an yanıt vermiyor.$suffix'),
    _ => Failure('http-$status', 'Sağlayıcı hatası ($status).$suffix'),
  };
}

Failure _transportFailure(TransportException e) => switch (e.kind) {
      TransportErrorKind.offline => const Failure('offline', 'Sağlayıcıya ulaşılamıyor. İnternet bağlantını kontrol et.'),
      TransportErrorKind.timeout => const Failure('timeout', 'Sağlayıcı zamanında yanıt vermedi.'),
      TransportErrorKind.tls => const Failure('tls', 'Güvenli bağlantı kurulamadı.'),
      TransportErrorKind.other => Failure('network', 'Ağ hatası: ${e.message}'),
    };

/// OpenAI Responses API (POST /v1/responses). Eski Assistants API kullanılmaz.
class OpenAiResponsesClient implements LlmClient {
  OpenAiResponsesClient({required this.baseUrl, required this.apiKey, required this.model, required HttpTransport transport})
      : _t = transport;
  final String baseUrl;
  final String apiKey;
  final String model;
  final HttpTransport _t;

  @override
  Future<Result<LlmReply>> complete(LlmRequest r) async {
    if (model.isEmpty) return const Result.err(Failure('model', 'Model adı ayarlanmadı.'));
    final body = jsonEncode({
      'model': model,
      'instructions': r.instructions,
      'input': [for (final m in r.messages) {'role': m.role == LlmRole.user ? 'user' : 'assistant', 'content': m.text}],
      'max_output_tokens': r.maxOutputTokens,
      'store': false,
      if (r.webSearch) 'tools': [{'type': 'web_search'}],
    });
    try {
      final res = await _t.send('POST', Uri.parse('$baseUrl/responses'),
          headers: {'authorization': 'Bearer $apiKey'}, body: body, timeout: const Duration(seconds: 90));
      if (res.status != 200) return Result.err(_httpFailure(res.status, res.body));
      final j = jsonDecode(res.body) as Map<String, Object?>;
      final text = j['output_text'] is String ? j['output_text'] as String : _extract(j['output']);
      if (text.trim().isEmpty) return const Result.err(Failure('empty', 'Boş yanıt.'));
      final usage = j['usage'] as Map<String, Object?>?;
      return Result.ok(LlmReply(
        text: text.trim(),
        model: j['model'] as String?,
        inputTokens: (usage?['input_tokens'] as num?)?.toInt(),
        outputTokens: (usage?['output_tokens'] as num?)?.toInt(),
      ));
    } on TransportException catch (e) {
      return Result.err(_transportFailure(e));
    } on Object {
      return const Result.err(Failure('bad-response', 'Yanıt okunamadı.'));
    }
  }

  static String _extract(Object? output) {
    if (output is! List) return '';
    final b = StringBuffer();
    for (final item in output) {
      if (item is Map && item['type'] == 'message' && item['content'] is List) {
        for (final c in item['content'] as List) {
          if (c is Map && c['type'] == 'output_text' && c['text'] is String) b.write(c['text']);
        }
      }
    }
    return b.toString();
  }
}

/// OpenAI uyumlu Chat Completions (DeepSeek ve diğer uyumlu sağlayıcılar).
class ChatCompletionsClient implements LlmClient {
  ChatCompletionsClient({required this.baseUrl, required this.apiKey, required this.model, required HttpTransport transport})
      : _t = transport;
  final String baseUrl;
  final String apiKey;
  final String model;
  final HttpTransport _t;

  @override
  Future<Result<LlmReply>> complete(LlmRequest r) async {
    if (model.isEmpty) return const Result.err(Failure('model', 'Model adı ayarlanmadı.'));
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': r.instructions},
        for (final m in r.messages) {'role': m.role == LlmRole.user ? 'user' : 'assistant', 'content': m.text},
      ],
      'max_tokens': r.maxOutputTokens,
      'stream': false,
    });
    try {
      final res = await _t.send('POST', Uri.parse('$baseUrl/chat/completions'),
          headers: {'authorization': 'Bearer $apiKey'}, body: body, timeout: const Duration(seconds: 90));
      if (res.status != 200) return Result.err(_httpFailure(res.status, res.body));
      final j = jsonDecode(res.body) as Map<String, Object?>;
      final choices = j['choices'] as List?;
      final text = ((choices?.firstOrNull as Map?)?['message'] as Map?)?['content'] as String? ?? '';
      if (text.trim().isEmpty) return const Result.err(Failure('empty', 'Boş yanıt.'));
      final usage = j['usage'] as Map<String, Object?>?;
      return Result.ok(LlmReply(
        text: text.trim(),
        model: j['model'] as String?,
        inputTokens: (usage?['prompt_tokens'] as num?)?.toInt(),
        outputTokens: (usage?['completion_tokens'] as num?)?.toInt(),
      ));
    } on TransportException catch (e) {
      return Result.err(_transportFailure(e));
    } on Object {
      return const Result.err(Failure('bad-response', 'Yanıt okunamadı.'));
    }
  }
}

/// Bağlantı testi: GET {base}/models — model listesi ister, METİN ÜRETMEZ.
/// (Çoğu sağlayıcıda ücretsizdir; yine de istek sağlayıcıya gider.)
Future<Result<String>> testProviderConnection({
  required String baseUrl,
  required String apiKey,
  required HttpTransport transport,
}) async {
  if (baseUrl.isEmpty) return const Result.err(Failure('config', 'API adresi gerekli.'));
  if (apiKey.isEmpty) return const Result.err(Failure('config', 'API anahtarı gerekli.'));
  try {
    final res = await transport.send('GET', Uri.parse('$baseUrl/models'),
        headers: {'authorization': 'Bearer $apiKey'}, timeout: const Duration(seconds: 15));
    if (res.status != 200) return Result.err(_httpFailure(res.status, res.body));
    final j = jsonDecode(res.body);
    final count = j is Map && j['data'] is List ? (j['data'] as List).length : 0;
    return Result.ok('Bağlantı başarılı, anahtar geçerli ($count model listelendi).');
  } on TransportException catch (e) {
    return Result.err(_transportFailure(e));
  } on Object {
    return const Result.err(Failure('bad-response', 'Yanıt okunamadı.'));
  }
}
