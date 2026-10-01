import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/auth/auth_session.dart';

final class ChangeFeedRequest {
  ChangeFeedRequest(this.after, {this.limit = 50}) {
    if (after < 0 || after > 9223372036854775807 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid change feed bounds');
    }
  }
  final int after, limit;
  @override
  String toString() => 'ChangeFeedRequest[REDACTED]';
}

final class ChangeFeedResponse {
  const ChangeFeedResponse(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'ChangeFeedResponse[REDACTED]';
}

final class ChangeFeedTransportFailure implements Exception {
  const ChangeFeedTransportFailure(this.receivedStatus);
  final int? receivedStatus;
  @override
  String toString() => 'ChangeFeedTransportFailure[REDACTED]';
}

abstract interface class ChangeFeedTransport {
  Future<ChangeFeedResponse> send(
    ChangeFeedRequest request,
    AuthSession session,
    void Function() requireCurrent,
  );
}

/// One bounded GET. The receiver owns decoding, cursor expiry and retry policy.
/// Neither a response nor a successful HTTP status advances the local cursor.
final class HttpChangeFeedTransport implements ChangeFeedTransport {
  HttpChangeFeedTransport(
    this.base, {
    bool allowLocalHttp = false,
    this.timeout = const Duration(seconds: 20),
    this.maxResponseBytes = 128 * 1024 * 1024,
  }) {
    if ((base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        timeout <= Duration.zero ||
        maxResponseBytes < 1 ||
        maxResponseBytes > 128 * 1024 * 1024) {
      throw ArgumentError('Explicit secure change feed endpoint required');
    }
  }
  final Uri base;
  final Duration timeout;
  final int maxResponseBytes;

  @override
  Future<ChangeFeedResponse> send(
    ChangeFeedRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    int? status;
    try {
      return await (() async {
        requireCurrent();
        final outgoing = await client.getUrl(
          base
              .resolve('/v1/sync/changes')
              .replace(
                queryParameters: {
                  'after_seq': '${request.after}',
                  'limit': '${request.limit}',
                },
              ),
        );
        requireCurrent();
        outgoing.followRedirects = false;
        outgoing.headers.set(HttpHeaders.acceptHeader, 'application/json');
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.accessToken}',
        );
        outgoing.headers.set('X-Device-Id', session.deviceId);
        final response = await outgoing.close();
        status = response.statusCode;
        final bytes = <int>[];
        await for (final chunk in response) {
          requireCurrent();
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const FormatException('Change feed response too large');
          }
          bytes.addAll(chunk);
        }
        requireCurrent();
        return ChangeFeedResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(timeout);
    } on SocketException {
      throw ChangeFeedTransportFailure(status);
    } on HttpException {
      throw ChangeFeedTransportFailure(status);
    } on TimeoutException {
      throw ChangeFeedTransportFailure(status);
    } on FormatException {
      throw ChangeFeedTransportFailure(status);
    } finally {
      client.close(force: true);
    }
  }
}
