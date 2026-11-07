import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HttpResult {
  const HttpResult(this.status, this.body);
  final int status;
  final String body;
}

enum TransportErrorKind { offline, timeout, tls, other }

class TransportException implements Exception {
  const TransportException(this.kind, this.message);
  final TransportErrorKind kind;
  final String message;
  @override
  String toString() => 'TransportException(${kind.name}): $message';
}

/// Testlerde sahtesiyle değiştirilebilen HTTP katmanı.
abstract interface class HttpTransport {
  Future<HttpResult> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 30),
  });
}

class IoHttpTransport implements HttpTransport {
  IoHttpTransport() : _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final HttpClient _client;

  @override
  Future<HttpResult> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final req = await _client.openUrl(method, url).timeout(timeout);
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      return HttpResult(res.statusCode, text);
    } on TimeoutException {
      throw const TransportException(TransportErrorKind.timeout, 'Zaman aşımı');
    } on HandshakeException catch (e) {
      throw TransportException(TransportErrorKind.tls, e.message);
    } on SocketException catch (e) {
      throw TransportException(TransportErrorKind.offline, e.message);
    } on HttpException catch (e) {
      throw TransportException(TransportErrorKind.other, e.message);
    }
  }

  void close() => _client.close(force: true);
}
