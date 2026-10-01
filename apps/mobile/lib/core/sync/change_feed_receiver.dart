import 'dart:convert';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import 'change_feed_response.dart';
import 'change_feed_transport.dart';

enum ChangeFeedStep {
  progressed,
  caughtUp,
  needsInitialSnapshot,
  cursorExpired,
  retryLater,
  authenticationRequired,
}

/// One page per invocation. No timers, automatic queued follow-ups or resync
/// writes. The existing application scheduler owns any subsequent invocation.
abstract interface class ChangeFeedStepper {
  Future<ChangeFeedStep> step(AuthSession session);
}

final class ChangeFeedReceiver implements ChangeFeedStepper {
  ChangeFeedReceiver({
    required this.store,
    required this.transport,
    required this.isSessionCurrent,
    this.newOperationId,
  });
  final AccountStore store;
  final ChangeFeedTransport transport;
  final bool Function(AuthSession) isSessionCurrent;
  final String Function()? newOperationId;
  Future<ChangeFeedStep>? _flight;
  bool _authenticationBlocked = false;

  /// The caller must have verified a fresh login before explicitly resuming.
  void resumeAfterAuthentication() => _authenticationBlocked = false;

  @override
  Future<ChangeFeedStep> step(AuthSession session) =>
      _flight ??= _step(session).whenComplete(() {
        _flight = null;
      });

  Future<ChangeFeedStep> _step(AuthSession session) async {
    void fence() {
      store.requireActive();
      if (session.userId != store.userId || !isSessionCurrent(session)) {
        throw StateError('Change feed session changed');
      }
    }

    fence();
    if (_authenticationBlocked) return ChangeFeedStep.authenticationRequired;
    final position = await store.readChangeFeedPosition();
    fence();
    if (position == null) return ChangeFeedStep.needsInitialSnapshot;
    final request = ChangeFeedRequest(position.cursor);
    final ChangeFeedResponse response;
    try {
      response = await transport.send(request, session, fence);
    } on ChangeFeedTransportFailure catch (error) {
      fence();
      if (error.receivedStatus == 401 || error.receivedStatus == 403) {
        _authenticationBlocked = true;
        return ChangeFeedStep.authenticationRequired;
      }
      return ChangeFeedStep.retryLater;
    }
    fence();
    if (response.status == 401 || response.status == 403) {
      _authenticationBlocked = true;
      return ChangeFeedStep.authenticationRequired;
    }
    if (response.status == 429 || response.status >= 500) {
      return ChangeFeedStep.retryLater;
    }
    if (response.status == 409) {
      final value = jsonDecode(response.body);
      if (value is Map &&
          value['error'] is Map &&
          value['error']['code'] == 'CURSOR_EXPIRED') {
        if (newOperationId != null) {
          fence();
          final requested = await store.requestSnapshotRefresh(
            expected: position,
            operationId: newOperationId!(),
          );
          fence();
          return requested
              ? ChangeFeedStep.needsInitialSnapshot
              : ChangeFeedStep.retryLater;
        }
        return ChangeFeedStep.cursorExpired;
      }
      throw const FormatException('Unexpected change feed conflict');
    }
    if (response.status != 200) {
      throw const FormatException('Unexpected change feed response');
    }
    final page = ChangeFeedPage.decode(
      response.body,
      owner: store.userId,
      expectedAfter: position.cursor,
      limit: request.limit,
    );
    fence();
    await store.applyChangeFeed(
      page,
      snapshotToken: position.snapshotToken,
      requireCurrent: fence,
    );
    fence();
    return page.hasMore ? ChangeFeedStep.progressed : ChangeFeedStep.caughtUp;
  }
}
