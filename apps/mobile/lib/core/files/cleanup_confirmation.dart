import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../domain/identifiers.dart';
import 'local_preservation.dart';

final class CleanupToken {
  CleanupToken(this.token, this.object, this.expires) {
    UuidValue(token);
  }
  factory CleanupToken.fromWire(Map<String, dynamic> row) => CleanupToken(
    UuidValue(row['token'] as String).value,
    PreservationObject(
      owner: row['user_id'] as String,
      recording: row['recording_id'] as String,
      generation: row['generation'] as String,
      checksum: row['sha256'] as String,
      size: row['size_bytes'] as int,
      revision: row['cloud_revision'] as int,
    ),
    DateTime.parse(row['expires_at'] as String).toUtc(),
  );
  final String token;
  final PreservationObject object;
  final DateTime expires;
  @override
  String toString() => 'CleanupToken[REDACTED]';
}

abstract interface class CleanupTransport {
  Future<void> confirmLocal(
    CleanupToken token,
    String operation,
    Future<void> Function() guard,
  );
}

abstract interface class CleanupStatusTransport {
  Future<String?> terminal(CleanupToken token, Future<void> Function() guard);
}

final class LocalCleanupCoordinator {
  LocalCleanupCoordinator(this.store, this.preservation, this.transport);
  final AccountStore store;
  final LocalPreservation preservation;
  final CleanupTransport transport;

  /// One recovery pass, never an expiry guess or a background request loop.
  Future<void> resume(CleanupStatusTransport status) async {
    final pending = await store.pendingLocalCleanup();
    for (final row in pending) {
      Future<void> guard() async => store.requireActive();
      final token = CleanupToken(
        row['token']! as String,
        PreservationObject(
          owner: store.userId,
          recording: row['recording_id']! as String,
          generation: row['generation']! as String,
          checksum: row['sha256']! as String,
          size: row['size_bytes']! as int,
          revision: row['cloud_revision']! as int,
        ),
        DateTime.fromMillisecondsSinceEpoch(
          row['expires_at']! as int,
          isUtc: true,
        ),
      );
      await guard();
      final terminal = await status.terminal(token, guard);
      await guard();
      if (terminal != null) {
        await store.finishLocalCleanupFence(
          token.token,
          token.object.generation,
          terminal,
        );
      }
    }
  }

  Future<void> confirm(CleanupToken token, {required String operation}) async {
    final object = token.object;
    Future<void> guard() async {
      store.requireActive();
      if (store.userId != object.owner) {
        throw StateError('Cleanup account changed');
      }
    }

    await guard();
    await preservation.verify(object);
    await guard();
    await store.beginLocalCleanupFence(
      token: token.token,
      owner: object.owner,
      recording: object.recording,
      generation: object.generation,
      checksum: object.checksum,
      size: object.size,
      revision: object.revision,
      expires: token.expires,
    );
    // Response loss must keep the durable fence: the server might already have confirmed.
    await transport.confirmLocal(token, UuidValue(operation).value, guard);
    await guard();
    await store.markLocalCleanupConfirmed(token.token);
  }
}

final class CleanupNetworkFailure implements Exception {
  const CleanupNetworkFailure();
}

final class HttpCleanupTransport
    implements CleanupTransport, CleanupStatusTransport {
  HttpCleanupTransport(
    this.base,
    this.session, {
    this.allowLocalHttp = false,
    this.timeout = const Duration(seconds: 30),
  }) {
    if (!(base.scheme == 'https' ||
            allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid cleanup API endpoint');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final bool allowLocalHttp;
  final Duration timeout;
  Future<CleanupToken> preview(
    String owner,
    String recording,
    String operation,
    Future<void> Function() guard,
  ) async {
    final id = UuidValue(recording).value;
    final response = await _post(
      '/v1/storage/cleanup-previews',
      owner,
      operation,
      {
        'recording_ids': [id],
      },
      guard,
    );
    if (response['items'] is! List || (response['items'] as List).length != 1) {
      throw const CleanupNetworkFailure();
    }
    final token = CleanupToken.fromWire(
      (response['items'] as List).single as Map<String, dynamic>,
    );
    if (token.object.owner != owner || token.object.recording != id) {
      throw const CleanupNetworkFailure();
    }
    return token;
  }

  @override
  Future<void> confirmLocal(
    CleanupToken token,
    String operation,
    Future<void> Function() guard,
  ) async {
    final auth = await session();
    await guard();
    final response = await _post(
      '/v1/storage/cleanup-confirmations',
      token.object.owner,
      operation,
      {
        'token': token.token,
        'mode': 'LOCAL_VERIFIED',
        'device_id': auth.deviceId,
        'sha256': token.object.checksum,
      },
      guard,
    );
    if (response['token'] != token.token ||
        response['state'] != 'CONFIRMED' ||
        DateTime.parse(response['expires_at'] as String).toUtc() !=
            token.expires) {
      throw const CleanupNetworkFailure();
    }
  }

  @override
  Future<String?> terminal(
    CleanupToken token,
    Future<void> Function() guard,
  ) async {
    final object = token.object;
    final response = await _request(
      'GET',
      '/v1/recordings/${object.recording}/retention',
      object.owner,
      null,
      null,
      guard,
      headers: {'X-Cleanup-Confirmation-Id': token.token},
    );
    final result = response['cleanup_confirmation'];
    if (response['recording_id'] != object.recording ||
        result is! Map ||
        result['token'] != token.token ||
        result['user_id'] != object.owner ||
        result['recording_id'] != object.recording ||
        result['generation'] != object.generation ||
        !{
          'WAITING_CONFIRMATION',
          'CONFIRMED',
          'DELETING',
          'RETRY_WAIT',
          'SUCCEEDED',
          'CANCELLED',
          'EXPIRED',
        }.contains(result['state'])) {
      throw const CleanupNetworkFailure();
    }
    return {'SUCCEEDED', 'CANCELLED', 'EXPIRED'}.contains(result['state'])
        ? result['state'] as String
        : null;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    String owner,
    String operation,
    Map<String, Object> body,
    Future<void> Function() guard,
  ) => _request('POST', path, owner, operation, body, guard);

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    String owner,
    String? operation,
    Map<String, Object>? body,
    Future<void> Function() guard, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        await guard();
        final auth = await session();
        await guard();
        if (auth.userId != owner) {
          throw const CleanupNetworkFailure();
        }
        final request = await client.openUrl(method, base.resolve(path));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set('Authorization', 'Bearer ${auth.accessToken}');
        request.headers.set('X-Device-Id', auth.deviceId);
        if (operation != null) {
          request.headers.set('Idempotency-Key', UuidValue(operation).value);
        }
        headers.forEach(request.headers.set);
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != 200 || response.contentLength > 16384) {
          throw const CleanupNetworkFailure();
        }
        final buffer = BytesBuilder(copy: false);
        var size = 0;
        await for (final bytes in response) {
          size += bytes.length;
          if (size > 16384) {
            throw const CleanupNetworkFailure();
          }
          buffer.add(bytes);
        }
        await guard();
        final value = jsonDecode(utf8.decode(buffer.takeBytes()));
        if (value is! Map<String, dynamic>) {
          throw const CleanupNetworkFailure();
        }
        return value;
      })().timeout(timeout);
    } catch (_) {
      throw const CleanupNetworkFailure();
    } finally {
      client.close(force: true);
    }
  }
}
