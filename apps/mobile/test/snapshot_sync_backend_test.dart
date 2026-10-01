import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';
import 'package:song_record/features/sync/sync_controller.dart';

class Sender implements SyncBackend {
  int sends = 0;
  @override
  bool automaticFollowupAllowed = true;
  @override
  Future<List<SyncItem>> load() async => [];
  @override
  Future<void> send() async {
    sends++;
  }

  @override
  Future<bool> retry(String id, int attempt) async => false;
  @override
  Future<DateTime?> nextAttempt() async => null;
}

class Receiver implements SnapshotStepper {
  int calls = 0;
  late Future<SnapshotStep> Function() action;
  @override
  Future<SnapshotStep> step(AuthSession session) {
    calls++;
    return action();
  }
}

void main() {
  final auth = AuthSession(
    userId: 'synthetic',
    deviceId: 'synthetic',
    accessToken: 'synthetic',
    refreshToken: 'unused',
    accessExpiresAt: DateTime.utc(2030),
    refreshExpiresAt: DateTime.utc(2030),
  );
  for (final status in [401, 403]) {
    test(
      'session rejection $status blocks receiving and later sending',
      () async {
        final sender = Sender(), receiver = Receiver();
        var lookups = 0;
        final backend = SnapshotSyncBackend(
          outgoing: sender,
          receiver: receiver,
          session: () async {
            lookups++;
            throw AuthFailure('synthetic', status: status);
          },
        );
        await backend.send();
        await backend.send();
        expect(lookups, 1);
        expect(receiver.calls, 0);
        expect(sender.sends, 0);
        expect(backend.automaticFollowupAllowed, isFalse);
        expect(await backend.nextAttempt(), isNull);
      },
    );
  }
  test(
    'temporary receive failure is passed to the controller without sending',
    () async {
      final sender = Sender(), receiver = Receiver();
      receiver.action = () async => SnapshotStep.retryLater;
      final backend = SnapshotSyncBackend(
        outgoing: sender,
        receiver: receiver,
        session: () async => auth,
      );
      await expectLater(backend.send(), throwsA(isA<AuthFailure>()));
      expect(sender.sends, 0);
      expect(backend.automaticFollowupAllowed, isTrue);
      receiver.action = () async => SnapshotStep.complete;
      await backend.send();
      expect(sender.sends, 1);
    },
  );
  test('only a complete baseline releases outgoing work; build status has a deadline', () async {
    var now = DateTime.utc(2026, 10, 1);
    final sender = Sender(), receiver = Receiver();
    receiver.action = () async => SnapshotStep.waiting;
    final backend = SnapshotSyncBackend(
      outgoing: sender,
      receiver: receiver,
      session: () async => auth,
      now: () => now,
    );
    await backend.send();
    await backend.send();
    expect(receiver.calls, 1);
    expect(sender.sends, 0);
    expect(await backend.nextAttempt(), now.add(const Duration(seconds: 5)));
    now = now.add(const Duration(seconds: 5));
    receiver.action = () async => SnapshotStep.complete;
    await backend.send();
    await backend.send();
    expect(receiver.calls, 2);
    expect(sender.sends, 2);
  });
  test('lifecycle wake queued during authentication rejection cannot send follow-up', () async {
    final receiver = Receiver(), sender = Sender();
    final gate = Completer<SnapshotStep>(), arrived = Completer<void>();
    receiver.action = () {
      arrived.complete();
      return gate.future;
    };
    final backend = SnapshotSyncBackend(
      outgoing: sender,
      receiver: receiver,
      session: () async => auth,
    );
    final controller = SyncController(
      backend,
      schedule: (delay, action) => () {},
    );
    controller.setEnabled(true);
    await arrived.future;
    controller.setForeground(false);
    controller.setForeground(true);
    gate.complete(SnapshotStep.authenticationRequired);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(receiver.calls, 1);
    expect(sender.sends, 0);
    expect(backend.automaticFollowupAllowed, isFalse);
    expect(await backend.nextAttempt(), isNull);
    await controller.wake();
    expect(receiver.calls, 1);
    expect(sender.sends, 0);
    controller.dispose();
  });
}
