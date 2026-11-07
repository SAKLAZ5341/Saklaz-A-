import 'dart:convert';

import 'package:saklaz_core/saklaz_core.dart';

import 'http_transport.dart';
import 'llm.dart';

/// SAKLAZ Gateway bağlantı ayarları. OpenAI anahtarı burada YOKTUR; yalnızca
/// gateway'in bu cihaza verdiği iptal edilebilir cihaz tokenı vardır.
class GatewayConfig {
  const GatewayConfig({required this.baseUrl, required this.deviceToken, this.model = ''});

  final String baseUrl;
  final String deviceToken;

  /// Boşsa gateway'in varsayılan modeli kullanılır.
  final String model;

  bool get isComplete => _uri != null && deviceToken.trim().length >= 16;

  Uri? get _uri {
    final u = Uri.tryParse(baseUrl.trim());
    if (u == null || !(u.isScheme('https') || u.isScheme('http')) || u.host.isEmpty) return null;
    return u;
  }

  bool get isHttps => _uri?.isScheme('https') ?? false;

  Uri endpoint(String path) {
    final u = _uri!;
    final base = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
    return u.replace(path: '$base$path');
  }
}

class GatewayStatus {
  const GatewayStatus({
    required this.defaultModel,
    required this.allowedModels,
    required this.requestsToday,
    required this.dailyRequestLimit,
    required this.costTodayUsd,
    required this.dailyBudgetUsd,
    required this.upstreamConfigured,
  });

  final String defaultModel;
  final List<String> allowedModels;
  final int requestsToday;
  final int dailyRequestLimit;
  final double costTodayUsd;
  final double dailyBudgetUsd;
  final bool upstreamConfigured;
}

/// Gateway hata kodları -> kullanıcıya gösterilecek Türkçe açıklama.
abstract final class GatewayErrors {
  static Failure fromHttp(int status, String body) {
    String? code;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) code = (j['error'] as Map)['code'] as String?;
    } on FormatException {
      // gövde JSON değil
    }
    return switch ((status, code)) {
      (401, _) => const Failure('auth', 'Gateway cihaz tokenını kabul etmedi. Ayarlardan tokenı kontrol et.'),
      (402, _) => const Failure('budget', 'Günlük bulut bütçesi doldu. Yarın tekrar dene veya bütçeyi artır.'),
      (429, _) => const Failure('rate-limit', 'Çok sık istek gönderildi. Biraz bekleyip tekrar dene.'),
      (413, _) => const Failure('too-large', 'İstek çok uzun.'),
      (400, 'model_not_allowed') => const Failure('model', 'Seçilen model gateway tarafından izinli değil.'),
      (503, 'not_configured') => const Failure('upstream-config', 'Gateway çalışıyor ama OpenAI anahtarı tanımlı değil.'),
      (502 || 504, _) => const Failure('upstream', 'OpenAI şu an yanıt vermiyor. Biraz sonra tekrar dene.'),
      _ => Failure('http-$status', 'Gateway beklenmeyen bir hata döndürdü ($status).'),
    };
  }

  static Failure fromTransport(TransportException e) => switch (e.kind) {
        TransportErrorKind.offline => const Failure('offline', 'Gateway\'e ulaşılamıyor. İnternet bağlantını veya gateway adresini kontrol et.'),
        TransportErrorKind.timeout => const Failure('timeout', 'Gateway zamanında yanıt vermedi.'),
        TransportErrorKind.tls => const Failure('tls', 'Güvenli bağlantı (TLS) kurulamadı.'),
        TransportErrorKind.other => Failure('network', 'Ağ hatası: ${e.message}'),
      };
}

/// OpenAI Responses API'ye SAKLAZ Gateway üzerinden erişen istemci.
class GatewayClient implements LlmClient {
  GatewayClient(this.config, this._transport);

  final GatewayConfig config;
  final HttpTransport _transport;

  Map<String, String> get _auth => {'authorization': 'Bearer ${config.deviceToken.trim()}'};

  static const notConfigured = Failure('not-configured', 'Bulut bağlantısı ayarlanmadı (gateway adresi ve token gerekli).');

  /// Kimlik doğrulamasız canlılık kontrolü.
  Future<Result<String>> health() async {
    if (!config.isComplete) return const Result.err(notConfigured);
    try {
      final r = await _transport.send('GET', config.endpoint('/health'), timeout: const Duration(seconds: 8));
      if (r.status != 200) return Result.err(GatewayErrors.fromHttp(r.status, r.body));
      final j = jsonDecode(r.body) as Map<String, Object?>;
      return Result.ok((j['version'] as String?) ?? '?');
    } on TransportException catch (e) {
      return Result.err(GatewayErrors.fromTransport(e));
    } on FormatException {
      return const Result.err(Failure('bad-response', 'Gateway yanıtı okunamadı.'));
    }
  }

  /// Kimlik doğrulamalı durum: token geçerli mi, kota/bütçe ne durumda?
  /// OpenAI'a istek GÖNDERMEZ (maliyetsiz).
  Future<Result<GatewayStatus>> status() async {
    if (!config.isComplete) return const Result.err(notConfigured);
    try {
      final r = await _transport.send('GET', config.endpoint('/v1/status'), headers: _auth, timeout: const Duration(seconds: 10));
      if (r.status != 200) return Result.err(GatewayErrors.fromHttp(r.status, r.body));
      final j = jsonDecode(r.body) as Map<String, Object?>;
      final usage = j['usage'] as Map<String, Object?>;
      return Result.ok(GatewayStatus(
        defaultModel: j['defaultModel'] as String,
        allowedModels: (j['allowedModels'] as List).cast<String>(),
        requestsToday: (usage['requestsToday'] as num).toInt(),
        dailyRequestLimit: (usage['dailyRequestLimit'] as num).toInt(),
        costTodayUsd: (usage['costTodayUsd'] as num).toDouble(),
        dailyBudgetUsd: (usage['dailyBudgetUsd'] as num).toDouble(),
        upstreamConfigured: j['upstreamConfigured'] as bool,
      ));
    } on TransportException catch (e) {
      return Result.err(GatewayErrors.fromTransport(e));
    } on Object {
      return const Result.err(Failure('bad-response', 'Gateway durum yanıtı okunamadı.'));
    }
  }

  @override
  Future<Result<LlmReply>> complete(LlmRequest request) async {
    if (!config.isComplete) return const Result.err(notConfigured);
    final body = jsonEncode({
      if (config.model.trim().isNotEmpty) 'model': config.model.trim(),
      'instructions': request.instructions,
      'messages': [for (final m in request.messages) m.toJson()],
      'maxOutputTokens': request.maxOutputTokens,
      'webSearch': request.webSearch,
    });
    try {
      final r = await _transport.send(
        'POST',
        config.endpoint('/v1/respond'),
        headers: _auth,
        body: body,
        timeout: const Duration(seconds: 60),
      );
      if (r.status != 200) return Result.err(GatewayErrors.fromHttp(r.status, r.body));
      final j = jsonDecode(r.body) as Map<String, Object?>;
      final text = (j['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) return const Result.err(Failure('empty', 'Bulut boş yanıt döndürdü.'));
      final usage = j['usage'] as Map<String, Object?>?;
      return Result.ok(LlmReply(
        text: text,
        model: j['model'] as String?,
        inputTokens: (usage?['inputTokens'] as num?)?.toInt(),
        outputTokens: (usage?['outputTokens'] as num?)?.toInt(),
        costUsd: (j['costUsd'] as num?)?.toDouble(),
      ));
    } on TransportException catch (e) {
      return Result.err(GatewayErrors.fromTransport(e));
    } on Object {
      return const Result.err(Failure('bad-response', 'Bulut yanıtı okunamadı.'));
    }
  }
}
