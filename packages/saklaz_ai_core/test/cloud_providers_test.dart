// MOCK TESTİ: gerçek sağlayıcıya istek gönderilmez.
import 'dart:convert';

import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:test/test.dart';

class FakeTransport implements HttpTransport {
  FakeTransport(this.status, this.body);
  final int status;
  final Object body;
  final calls = <(String, Uri, Map<String, String>, String?)>[];
  @override
  Future<HttpResult> send(String method, Uri url,
      {Map<String, String> headers = const {}, String? body, Duration timeout = const Duration(seconds: 30)}) async {
    calls.add((method, url, headers, body));
    return HttpResult(status, jsonEncode(this.body));
  }
}

const req = LlmRequest(instructions: 'ins', messages: [LlmMessage(LlmRole.user, 'selam')]);

void main() {
  test('sağlayıcılar varsayılan olarak pasif', () {
    for (final k in ProviderKind.values) {
      expect(ProviderSettings(kind: k).enabled, isFalse);
    }
  });

  test('OpenAI Responses API isteği', () async {
    final t = FakeTransport(200, {
      'model': 'm',
      'output': [
        {'type': 'message', 'content': [{'type': 'output_text', 'text': 'Merhaba'}]},
      ],
    });
    final c = OpenAiResponsesClient(baseUrl: 'https://api.openai.com/v1', apiKey: 'k', model: 'm', transport: t);
    expect((await c.complete(req)).valueOrNull?.text, 'Merhaba');
    final (_, url, headers, body) = t.calls.single;
    expect(url.toString(), 'https://api.openai.com/v1/responses');
    expect(headers['authorization'], 'Bearer k');
    final j = jsonDecode(body!) as Map;
    expect(j['store'], false);
    expect(j['input'], [{'role': 'user', 'content': 'selam'}]);
  });

  test('DeepSeek / uyumlu Chat Completions isteği', () async {
    final t = FakeTransport(200, {
      'choices': [
        {'message': {'content': 'Selam'}},
      ],
    });
    final c = ChatCompletionsClient(baseUrl: 'https://api.deepseek.com', apiKey: 'k', model: 'deepseek-chat', transport: t);
    expect((await c.complete(req)).valueOrNull?.text, 'Selam');
    final j = jsonDecode(t.calls.single.$4!) as Map;
    expect((j['messages'] as List).first, {'role': 'system', 'content': 'ins'});
    expect(t.calls.single.$2.path, '/chat/completions');
  });

  test('hata eşlemesi: 401 / 402 / 429', () async {
    for (final (code, expected) in [(401, 'auth'), (402, 'budget'), (429, 'rate-limit')]) {
      final c = ChatCompletionsClient(baseUrl: 'https://x', apiKey: 'k', model: 'm', transport: FakeTransport(code, {'error': {'message': 'x'}}));
      expect((await c.complete(req)).failureOrNull?.code, expected);
    }
  });

  test('bağlantı testi metin üretmez (GET /models)', () async {
    final t = FakeTransport(200, {'data': [{'id': 'a'}, {'id': 'b'}]});
    final r = await testProviderConnection(baseUrl: 'https://api.deepseek.com', apiKey: 'k', transport: t);
    expect(r.valueOrNull, contains('2 model'));
    expect(t.calls.single.$1, 'GET');
    expect(t.calls.single.$2.path, '/models');
  });
}
