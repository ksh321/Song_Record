import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/auth/auth_session.dart';
import 'mutation_request.dart';

abstract interface class MutationTransport {
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() requireCurrent,
  );
}

/// Only transport-level uncertainty, never a database or programming failure.
final class MutationNetworkFailure implements Exception {
  const MutationNetworkFailure({this.receivedStatus});
  final int? receivedStatus;
}

final class MutationBodyFailure implements Exception {
  const MutationBodyFailure(this.receivedStatus);
  final int? receivedStatus;
}

/// No redirects or automatic retries. A lost response retains the frozen request.
final class HttpMutationTransport implements MutationTransport {
  HttpMutationTransport(
    this.base, {
    bool allowLocalHttp = false,
    this.timeout = const Duration(seconds: 20),
  }) {
    if ((base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError(
        'HTTPS or an explicit local development endpoint required',
      );
    }
  }
  final Uri base;
  final Duration timeout;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    int? receivedStatus;
    try {
      return await (() async {
        requireCurrent();
        final outgoing = await client.openUrl(
          request.method,
          base.resolve(request.path),
        );
        requireCurrent(); // Account may change while opening the connection.
        outgoing.followRedirects = false;
        outgoing.headers.contentType = ContentType.json;
        outgoing.headers.set(HttpHeaders.acceptHeader, 'application/json');
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.accessToken}',
        );
        outgoing.headers.set('X-Device-Id', session.deviceId);
        outgoing.headers.set('Idempotency-Key', request.mutation.opId);
        outgoing.add(utf8.encode(request.body));
        final response = await outgoing.close();
        receivedStatus = response.statusCode;
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1048576) {
            throw const FormatException('Response too large');
          }
          bytes.addAll(chunk);
        }
        return MutationResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(timeout);
    } on FormatException {
      throw MutationBodyFailure(receivedStatus);
    } on SocketException {
      throw MutationNetworkFailure(receivedStatus: receivedStatus);
    } on TimeoutException {
      throw MutationNetworkFailure(receivedStatus: receivedStatus);
    } on HttpException {
      throw MutationNetworkFailure(receivedStatus: receivedStatus);
    } finally {
      client.close(force: true);
    }
  }
}
