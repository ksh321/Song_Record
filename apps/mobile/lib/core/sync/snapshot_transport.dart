import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/auth/auth_session.dart';
import '../domain/identifiers.dart';
import 'snapshot_response.dart';

final class SnapshotHttpResponse {
  const SnapshotHttpResponse(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'SnapshotHttpResponse[REDACTED]';
}

final class SnapshotTransportFailure implements Exception {
  const SnapshotTransportFailure(this.status);
  final int? status;
}

/// Closed route constructors prevent a server-supplied URL receiving credentials.
final class SnapshotHttpRequest {
  SnapshotHttpRequest.create(String operationId)
    : method = 'POST',
      path = '/v1/sync/snapshots',
      operationId = UuidValue(operationId).value,
      query = const {},
      includeTrash = null,
      sourceUserId = null;

  SnapshotHttpRequest.status(String token)
    : method = 'GET',
      path = '/v1/sync/snapshots/${UuidValue(token).value}',
      operationId = null,
      query = const {},
      includeTrash = null,
      sourceUserId = null;

  SnapshotHttpRequest.page(String token, String entity, {String? cursor})
    : method = 'GET',
      path = '/v1/sync/snapshots/${UuidValue(token).value}',
      operationId = null,
      includeTrash = null,
      sourceUserId = null,
      query = Map.unmodifiable({
        'entity': entity,
        'limit': '50',
        'cursor': ?cursor,
      }) {
    if (!snapshotEntities.contains(entity) ||
        (cursor != null &&
            (!cursor.startsWith('sp1.') || cursor.length > 4096))) {
      throw ArgumentError('Invalid snapshot page request');
    }
  }

  final String method, path;
  SnapshotHttpRequest.exportCreate(String operationId, bool trash)
    : method = 'POST',
      path = '/v1/exports',
      operationId = UuidValue(operationId).value,
      query = const {},
      includeTrash = trash,
      sourceUserId = null;
  SnapshotHttpRequest.exportManifest(
    String id, {
    String? entity,
    String? cursor,
  }) : method = 'GET',
       path = '/v1/exports/${UuidValue(id).value}/manifest',
       operationId = null,
       includeTrash = null,
       sourceUserId = null,
       query = Map.unmodifiable({
         'entity': ?entity,
         if (entity != null) 'limit': '50',
         'cursor': ?cursor,
       }) {
    if ((entity != null && !snapshotEntities.contains(entity)) ||
        (cursor != null &&
            (entity == null ||
                !cursor.startsWith('sp1.') ||
                cursor.length > 4096))) {
      throw ArgumentError('Invalid export page request');
    }
  }
  SnapshotHttpRequest.importPreflight(String operationId, String sourceUserId)
    : method = 'POST',
      path = '/v1/imports/preflight',
      operationId = UuidValue(operationId).value,
      query = const {},
      includeTrash = null,
      sourceUserId = UuidValue(sourceUserId).value;
  final String? sourceUserId;
  final bool? includeTrash;
  final String? operationId;
  final Map<String, String> query;
  @override
  String toString() => 'SnapshotHttpRequest[REDACTED]';
}

abstract interface class SnapshotTransport {
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() requireCurrent,
  );
}

/// One bounded attempt; callers retain the durable operation ID on uncertainty.
final class HttpSnapshotTransport implements SnapshotTransport {
  HttpSnapshotTransport(
    this.base, {
    bool allowLocalHttp = false,
    this.timeout = const Duration(seconds: 20),
  }) {
    if ((base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        timeout <= Duration.zero) {
      throw ArgumentError('Explicit secure snapshot endpoint required');
    }
  }
  final Uri base;
  final Duration timeout;

  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    int? status;
    try {
      return await (() async {
        requireCurrent();
        final outgoing = await client.openUrl(
          request.method,
          base.resolve(request.path).replace(queryParameters: request.query),
        );
        requireCurrent();
        outgoing.followRedirects = false;
        outgoing.headers.set(HttpHeaders.acceptHeader, 'application/json');
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.accessToken}',
        );
        outgoing.headers.set('X-Device-Id', session.deviceId);
        if (request.operationId != null) {
          outgoing.headers.contentType = ContentType.json;
          outgoing.headers.set('Idempotency-Key', request.operationId!);
          outgoing.add(
            utf8.encode(
              jsonEncode(
                request.includeTrash == null
                    ? {
                        'schema_version': 1,
                        'source_user_id': ?request.sourceUserId,
                      }
                    : {'include_trash': request.includeTrash},
              ),
            ),
          );
        }
        final response = await outgoing.close();
        status = response.statusCode;
        final bytes = <int>[];
        await for (final chunk in response) {
          // A 50-row page carries both parsed and canonical payloads. Still bound
          // total memory independently of the server's response headers.
          if (bytes.length + chunk.length > 128 * 1024 * 1024) {
            throw const FormatException('Snapshot response too large');
          }
          bytes.addAll(chunk);
        }
        requireCurrent();
        return SnapshotHttpResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(timeout);
    } on SocketException {
      throw SnapshotTransportFailure(status);
    } on HttpException {
      throw SnapshotTransportFailure(status);
    } on TimeoutException {
      throw SnapshotTransportFailure(status);
    } on FormatException {
      throw SnapshotTransportFailure(status);
    } finally {
      client.close(force: true);
    }
  }
}
