import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.rawBody,
  });

  final String status;
  final String rawBody;
}

class HealthCheckException implements Exception {
  const HealthCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef HealthLoader = Future<HealthResponse> Function();

class HealthClient {
  HealthClient({
    required this.apiBaseUrl,
    this.timeout = const Duration(seconds: 5),
  });

  final Uri apiBaseUrl;
  final Duration timeout;

  Uri get healthUri => apiBaseUrl.resolve('/actuator/health');

  Future<HealthResponse> fetch() async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(healthUri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HealthCheckException(
          '서버가 HTTP ${response.statusCode}을 반환했습니다.',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['status'] is! String) {
        throw const HealthCheckException(
          '서버 health 응답 형식이 올바르지 않습니다.',
        );
      }

      return HealthResponse(
        status: decoded['status'] as String,
        rawBody: body,
      );
    } on TimeoutException {
      throw const HealthCheckException('서버 응답 시간이 초과됐습니다.');
    } on SocketException {
      throw const HealthCheckException(
        '서버에 연결할 수 없습니다. API 주소와 서버 실행 상태를 확인하세요.',
      );
    } on FormatException {
      throw const HealthCheckException(
        '서버가 올바른 JSON을 반환하지 않았습니다.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
