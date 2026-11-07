// MOCK TESTİ: Gerçek gateway veya OpenAI ile konuşmaz; sahte HTTP katmanı kullanır.
import 'dart:convert';

import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:test/test.dart';

class FakeTransport implements HttpTransport {
  FakeTransport(this.handler);
  final HttpResult Function(String method, Uri url, Map<String, String> headers, String? body) handler;
  final calls = <(String, Uri, Map<String, String>, String?)>[];
  TransportException? throwing;

  @override
  Future<HttpResult> send(String method, Uri url,
      {Map<String, String> headers = const {}, String? body, Duration timeout = const Duration(seconds: 30)}) async {
    calls.add((method, url, headers, body));
    if (throwing != null) throw throwing!;
    return handler(method, url, headers, body);
  }
}

const cfg = GatewayConfig(baseUrl: 'https://gw.example.com/api/', deviceToken: 'tok_0123456789abcdef', model: 'test-model');

void main() {
  test('eksik ayarda istek göndermez', () async {
    final t = FakeTransport((_, _, _, _) => const HttpResult(200, '{}'));
    final c = GatewayClient(const GatewayConfig(baseUrl: '', deviceToken: ''), t);
    final r = await c.complete(const LlmRequest(instructions: 'x', messages: []));
    expect(r.failureOrNull?.code, 'not-configured');
    expect(t.calls, isEmpty);
  });

  test('istek biçimi: Bearer token, model, mesajlar; OpenAI anahtarı YOK', () async {
    final t = FakeTransport((_, _, _, _) => HttpResult(200, jsonEncode({
          'text': 'Merhaba!',
          'model': 'test-model',
          'usage': {'inputTokens': 10, 'outputTokens': 3},
          'costUsd': 0.0001,
        })));
    final c = GatewayClient(cfg, t);
    final r = await c.complete(const LlmRequest(
      instructions: 'ins',
      messages: [LlmMessage(LlmRole.user, 'selam')],
      webSearch: true,
    ));
    expect(r.valueOrNull?.text, 'Merhaba!');
    expect(r.valueOrNull?.outputTokens, 3);
    final (method, url, headers, body) = t.calls.single;
    expect(method, 'POST');
    expect(url.toString(), 'https://gw.example.com/api/v1/respond');
    expect(headers['authorization'], 'Bearer tok_0123456789abcdef');
    final j = jsonDecode(body!) as Map<String, Object?>;
    expect(j['model'], 'test-model');
    expect(j['webSearch'], true);
    expect(j['messages'], [
      {'role': 'user', 'text': 'selam'},
    ]);
    expect(body.toLowerCase(), isNot(contains('sk-')));
  });

  test('HTTP hataları anlaşılır Türkçe hatalara dönüşür', () async {
    Future<String?> codeFor(int status, [String body = '{}']) async {
      final c = GatewayClient(cfg, FakeTransport((_, _, _, _) => HttpResult(status, body)));
      return (await c.complete(const LlmRequest(instructions: 'x', messages: []))).failureOrNull?.code;
    }

    expect(await codeFor(401), 'auth');
    expect(await codeFor(402), 'budget');
    expect(await codeFor(429), 'rate-limit');
    expect(await codeFor(502), 'upstream');
    expect(await codeFor(503, '{"error":{"code":"not_configured"}}'), 'upstream-config');
    expect(await codeFor(400, '{"error":{"code":"model_not_allowed"}}'), 'model');
  });

  test('bağlantı yoksa "offline" hatası', () async {
    final t = FakeTransport((_, _, _, _) => const HttpResult(200, '{}'))
      ..throwing = const TransportException(TransportErrorKind.offline, 'no route');
    final r = await GatewayClient(cfg, t).complete(const LlmRequest(instructions: 'x', messages: []));
    expect(r.failureOrNull?.code, 'offline');
    expect(r.failureOrNull?.message, contains('ulaşılamıyor'));
  });

  test('status: token doğrulanır, maliyet bilgisi okunur', () async {
    final t = FakeTransport((_, _, _, _) => HttpResult(200, jsonEncode({
          'defaultModel': 'm1',
          'allowedModels': ['m1', 'm2'],
          'upstreamConfigured': true,
          'usage': {'requestsToday': 3, 'dailyRequestLimit': 200, 'costTodayUsd': 0.01, 'dailyBudgetUsd': 1.0},
        })));
    final r = await GatewayClient(cfg, t).status();
    expect(r.valueOrNull?.allowedModels, ['m1', 'm2']);
    expect(r.valueOrNull?.dailyBudgetUsd, 1.0);
    expect(t.calls.single.$2.path, '/api/v1/status');
  });
}
