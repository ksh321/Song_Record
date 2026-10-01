import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';
import 'package:song_record/features/sync/sync_controller.dart';
import 'package:song_record/features/sync/sync_screen.dart';

import 'snapshot_sync_backend_test.dart' show Sender, Receiver;

class FeedStepper implements ChangeFeedStepper {
  int calls = 0;
  late Future<ChangeFeedStep> Function() respond;
  @override
  Future<ChangeFeedStep> step(AuthSession session) {
    calls++;
    return respond();
  }
}

void main() {
  final session = AuthSession(
    userId: 'synthetic',
    deviceId: 'synthetic',
    accessToken: 'synthetic',
    refreshToken: 'unused',
    accessExpiresAt: DateTime.utc(2030),
    refreshExpiresAt: DateTime.utc(2030),
  );
  late Sender sender;
  late FeedStepper receiver;
  late ChangeFeedSyncBackend backend;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 10, 1);
    sender = Sender();
    receiver = FeedStepper();
    backend = ChangeFeedSyncBackend(
      outgoing: sender,
      receiver: receiver,
      session: () async => session,
      now: () => now,
    );
  });
  test(
    'more pages defer outgoing work and early wake cannot bypass delay',
    () async {
      receiver.respond = () async => ChangeFeedStep.progressed;
      await backend.send();
      await backend.send();
      expect(receiver.calls, 1);
      expect(sender.sends, 0);
      expect(await backend.nextAttempt(), now.add(const Duration(seconds: 1)));
      now = now.add(const Duration(seconds: 1));
      receiver.respond = () async => ChangeFeedStep.caughtUp;
      await backend.send();
      expect(sender.sends, 1);
      expect(receiver.calls, 2);
      await backend.send();
      expect(receiver.calls, 3);
      expect(sender.sends, 2);
    },
  );
  for (final result in [
    ChangeFeedStep.authenticationRequired,
    ChangeFeedStep.cursorExpired,
    ChangeFeedStep.needsInitialSnapshot,
  ]) {
    test(
      '$result blocks outgoing and automatic followup without deleting data',
      () async {
        receiver.respond = () async => result;
        await backend.send();
        await backend.send();
        expect(receiver.calls, 1);
        expect(sender.sends, 0);
        expect(backend.automaticFollowupAllowed, isFalse);
        expect(await backend.nextAttempt(), isNull);
        expect(backend.statusMessage, isNotNull);
      },
    );
  }
  for (final status in [401, 403]) {
    test('session lookup $status latches before receiver and sender', () async {
      backend = ChangeFeedSyncBackend(
        outgoing: sender,
        receiver: receiver,
        session: () async => throw AuthFailure('synthetic', status: status),
      );
      await backend.send();
      await backend.send();
      expect(receiver.calls, 0);
      expect(sender.sends, 0);
      expect(backend.automaticFollowupAllowed, isFalse);
    });
  }
  test(
    'temporary failures use controller recovery instead of transmitting',
    () async {
      receiver.respond = () async => ChangeFeedStep.retryLater;
      await expectLater(backend.send(), throwsA(isA<AuthFailure>()));
      expect(sender.sends, 0);
      expect(backend.automaticFollowupAllowed, isTrue);
      receiver.respond = () async => ChangeFeedStep.caughtUp;
      await backend.send();
      expect(sender.sends, 1);
    },
  );
  test('outgoing authentication block is retained after catchup', () async {
    receiver.respond = () async => ChangeFeedStep.caughtUp;
    sender.automaticFollowupAllowed = false;
    await backend.send();
    expect(backend.automaticFollowupAllowed, isFalse);
    expect(await backend.nextAttempt(), isNull);
  });
  test(
    'delayed authentication after leave-return suppresses queued followup',
    () async {
      final gate = Completer<ChangeFeedStep>(), arrived = Completer<void>();
      receiver.respond = () {
        arrived.complete();
        return gate.future;
      };
      final controller = SyncController(backend, schedule: (_, _) => () {});
      controller.setEnabled(true);
      await arrived.future;
      controller.setForeground(false);
      controller.setForeground(true);
      gate.complete(ChangeFeedStep.authenticationRequired);
      for (var n = 0; n < 10; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(receiver.calls, 1);
      expect(sender.sends, 0);
      await controller.wake();
      expect(receiver.calls, 1);
      expect(sender.sends, 0);
      controller.dispose();
    },
  );
  testWidgets('initial wrapper forwards delta status instead of empty queue', (
    tester,
  ) async {
    final initial = Receiver()..action = () async => SnapshotStep.complete;
    receiver.respond = () async => ChangeFeedStep.cursorExpired;
    final wrapper = SnapshotSyncBackend(
      outgoing: backend,
      receiver: initial,
      session: () async => session,
    );
    final controller = SyncController(wrapper, schedule: (_, _) => () {});
    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: controller)),
    );
    controller.setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('초기 정보를 다시'), findsOneWidget);
    expect(find.text('대기 중인 정보가 없어요.'), findsNothing);
    expect(sender.sends, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
