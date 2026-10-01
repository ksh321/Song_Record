import 'dart:convert';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../domain/identifiers.dart';
import 'snapshot_response.dart';
import 'snapshot_transport.dart';

enum SnapshotStep {
  progressed,
  waiting,
  retryLater,
  authenticationRequired,
  complete,
}

/// One network request at most per call. The application schedules the next step;
/// this class neither polls nor queues a follow-up behind an in-flight request.
abstract interface class SnapshotStepper {
  Future<SnapshotStep> step(AuthSession session);
}

final class SnapshotReceiver implements SnapshotStepper {
  SnapshotReceiver({
    required this.store,
    required this.transport,
    required this.newOperationId,
    required this.clock,
  });
  final AccountStore store;
  final SnapshotTransport transport;
  final String Function() newOperationId;
  final DateTime Function() clock;
  Future<SnapshotStep>? _flight;
  bool _authenticationBlocked = false;

  /// Only the caller that has obtained a newly verified session may resume.
  void resumeAfterAuthentication() => _authenticationBlocked = false;

  @override
  Future<SnapshotStep> step(AuthSession session) {
    return _flight ??= _step(session).whenComplete(() {
      _flight = null;
    });
  }

  Future<SnapshotStep> _step(AuthSession session) async {
    void fence() {
      store.requireActive();
      if (session.userId != store.userId) {
        throw StateError('Snapshot account changed');
      }
    }

    fence();
    if (_authenticationBlocked) return SnapshotStep.authenticationRequired;
    var observed = await store.readSnapshotResume();
    if (observed == null) {
      if (await store.hasCompleteBaseline()) return SnapshotStep.complete;
      final initial = {
        'version': 1,
        'op_id': UuidValue(newOperationId()).value,
        'phase': 'REQUESTED',
        'token': null,
        'expires_at': null,
      };
      if (!await store.compareAndSetSnapshotResume(
        expected: null,
        replacement: initial,
      )) {
        return SnapshotStep.waiting;
      }
      observed = await store.readSnapshotResume();
    }
    final state = _decode(observed!);
    final token = state['token'] as String?;
    final expiry = state['expires_at'] as String?;
    Future<SnapshotStep> restart() async {
      if (token != null) await store.discardSnapshotDownload(token);
      await store.compareAndSetSnapshotResume(
        expected: observed,
        replacement: null,
      );
      return SnapshotStep.progressed;
    }

    if (expiry != null && !clock().isBefore(DateTime.parse(expiry))) {
      return restart();
    }

    SnapshotHttpRequest request;
    String? entity;
    var ordinal = 0;
    if (state['phase'] == 'REQUESTED') {
      request = SnapshotHttpRequest.create(state['op_id'] as String);
    } else if (state['phase'] == 'BUILDING') {
      request = SnapshotHttpRequest.status(token!);
    } else {
      final download = await store.snapshotDownloadState(token!);
      for (final candidate in snapshotEntities) {
        if (download.progress[candidate]?.finished != true) {
          entity = candidate;
          break;
        }
      }
      if (entity == null) {
        await store.verifySnapshotDownload(token);
        fence();
        await store.applySnapshotDownload(token);
        return SnapshotStep.complete;
      }
      final progress = download.progress[entity];
      ordinal = progress?.ordinal ?? 0;
      request = SnapshotHttpRequest.page(
        token,
        entity,
        cursor: progress?.cursor,
      );
    }
    SnapshotHttpResponse response;
    try {
      response = await transport.send(request, session, fence);
    } on SnapshotTransportFailure catch (failure) {
      if (failure.status == 401 || failure.status == 403) {
        _authenticationBlocked = true;
        return SnapshotStep.authenticationRequired;
      }
      return SnapshotStep.retryLater;
    }
    fence();
    if (response.status == 401 || response.status == 403) {
      _authenticationBlocked = true;
      return SnapshotStep.authenticationRequired;
    }
    if (await store.readSnapshotResume() != observed) {
      return SnapshotStep.waiting;
    }
    if (response.status == 410 && token != null) return restart();
    if (response.status == 400 && entity != null) {
      final error = jsonDecode(response.body);
      if (error is Map &&
          error['error'] is Map &&
          error['error']['code'] == 'INVALID_CURSOR') {
        return restart();
      }
    }
    if (response.status == 429 || response.status >= 500) {
      return SnapshotStep.retryLater;
    }
    if (state['phase'] == 'REQUESTED' && response.status == 202) {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body.length != 4 ||
          body['status'] != 'BUILDING' ||
          body['snapshot_token'] is! String ||
          body['operation_id'] is! String) {
        throw const FormatException('Invalid snapshot receipt');
      }
      final issued = UuidValue(body['snapshot_token'] as String).value;
      UuidValue(body['operation_id'] as String);
      if (body['status_url'] != '/v1/sync/snapshots/$issued') {
        throw const FormatException('Invalid snapshot status path');
      }
      await store.compareAndSetSnapshotResume(
        expected: observed,
        replacement: {...state, 'phase': 'BUILDING', 'token': issued},
      );
      return SnapshotStep.progressed;
    }
    if (state['phase'] == 'BUILDING') {
      if (response.status == 202) {
        final body = jsonDecode(response.body);
        if (body is! Map ||
            body.length != 3 ||
            body['snapshot_token'] != token ||
            body['status'] != 'BUILDING' ||
            body['schema_version'] != 1) {
          throw const FormatException('Invalid snapshot build status');
        }
        return SnapshotStep.waiting;
      }
      if (response.status == 200) {
        final manifest = SnapshotManifest.decode(
          response.body,
          expectedToken: token!,
          now: clock(),
        );
        await store.beginSnapshotDownload(token, response.body);
        await store.compareAndSetSnapshotResume(
          expected: observed,
          replacement: {
            ...state,
            'phase': 'RECEIVING',
            'expires_at': manifest.expiresAt.toIso8601String(),
          },
        );
        return SnapshotStep.progressed;
      }
    }
    if (entity != null && response.status == 200) {
      await store.appendSnapshotPage(token!, entity, ordinal, response.body);
      return SnapshotStep.progressed;
    }
    throw const FormatException('Unexpected snapshot response');
  }

  Map<String, dynamic> _decode(String raw) {
    final state = jsonDecode(raw);
    if (state is! Map<String, dynamic> ||
        state.length != 5 ||
        state['version'] != 1 ||
        state['op_id'] is! String ||
        !{'REQUESTED', 'BUILDING', 'RECEIVING'}.contains(state['phase']) ||
        !state.containsKey('token') ||
        !state.containsKey('expires_at')) {
      throw const FormatException('Invalid snapshot resume');
    }
    UuidValue(state['op_id'] as String);
    if (state['phase'] == 'REQUESTED') {
      if (state['token'] != null || state['expires_at'] != null) {
        throw const FormatException('Invalid requested state');
      }
    } else {
      if (state['token'] is! String) {
        throw const FormatException('Missing snapshot token');
      }
      UuidValue(state['token'] as String);
      if (state['phase'] == 'RECEIVING') {
        if (state['expires_at'] is! String ||
            !DateTime.parse(state['expires_at'] as String).isUtc) {
          throw const FormatException('Invalid snapshot expiry');
        }
      } else if (state['expires_at'] != null) {
        throw const FormatException('Invalid building state');
      }
    }
    return state;
  }
}
