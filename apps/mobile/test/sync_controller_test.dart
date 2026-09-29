import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/features/sync/sync_controller.dart';
import 'package:song_record/features/sync/sync_screen.dart';

SyncItem item() => const SyncItem(
  QueuedMutation(
    opId: 'private-op',
    localOrder: 1,
    entity: LocalEntity.tag,
    entityId: 'private-entity',
    operation: LocalOperation.create,
    state: 'RETRY',
    baseRevision: 0,
    payload: 'private-content',
    attemptCount: 4,
  ),
  RetryStatus(
    opId: 'private-op',
    queueState: 'RETRY',
    attemptCount: 4,
    automaticRetriesClaimed: 3,
    mode: 'MANUAL_REQUIRED',
    lastAttemptKind: 'AUTO',
    nextAttemptAt: null,
  ),
);

class Backend implements SyncBackend {
  @override
  bool get automaticFollowupAllowed => true;
  List<SyncItem> items = [item()];
  int sends = 0, retries = 0, concurrent = 0, maximumConcurrent = 0;
  int deadlineQueries = 0;
  bool failLoad = false, acceptRetry = true;
  bool failSend = false, failNext = false;
  DateTime? due;
  Completer<void>? sending;
  Completer<List<SyncItem>>? loading;
  Completer<bool>? retrying;
  Completer<DateTime?>? nextLookup;
  @override
  Future<List<SyncItem>> load() async {
    if (failLoad) throw StateError('private-error');
    return loading?.future ?? items;
  }

  @override
  Future<void> send() async {
    sends++;
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    await sending?.future;
    concurrent--;
    if (failSend) throw StateError('injected send error');
  }

  @override
  Future<bool> retry(String opId, int expectedAttempt) async {
    expect(opId, 'private-op');
    expect(expectedAttempt, 4);
    retries++;
    return retrying?.future ?? acceptRetry;
  }

  @override
  Future<DateTime?> nextAttempt() async {
    deadlineQueries++;
    if (failNext) throw StateError('injected deadline error');
    return nextLookup?.future ?? due;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

class ScheduledWake {
  ScheduledWake(this.due, this.action);
  final DateTime due;
  final VoidCallback action;
  bool active = true;
}

class ScheduleHarness {
  DateTime now = DateTime.utc(2026, 9, 29);
  final tasks = <ScheduledWake>[];
  int maximumActive = 0;
  List<ScheduledWake> get active => tasks.where((t) => t.active).toList();
  VoidCallback schedule(Duration delay, VoidCallback action) {
    final task = ScheduledWake(now.add(delay), action);
    tasks.add(task);
    if (active.length > maximumActive) maximumActive = active.length;
    return () => task.active = false;
  }

  void fire() {
    final task = active.single;
    now = task.due;
    task.active = false;
    task.action();
  }
}

void main() {
  test('normal expired deadline has a one-second scheduling floor', () async {
    final harness = ScheduleHarness();
    final backend = Backend()
      ..due = harness.now.subtract(const Duration(minutes: 1));
    final controller = SyncController(
      backend,
      now: () => harness.now,
      schedule: harness.schedule,
    );
    controller.setEnabled(true);
    await flush();
    expect(
      harness.active.single.due.difference(harness.now),
      const Duration(seconds: 1),
    );
    controller.dispose();
  });

  test(
    'successful automatic recovery clears previous internal failures',
    () async {
      final harness = ScheduleHarness();
      final backend = Backend()..failSend = true;
      final controller = SyncController(
        backend,
        now: () => harness.now,
        schedule: harness.schedule,
      );
      controller.setEnabled(true);
      await flush();
      backend.failSend = false;
      harness.fire();
      await flush();
      expect(harness.active, isEmpty);
      backend.failSend = true;
      await controller.wake();
      harness.fire();
      await flush();
      expect(controller.needsResume, isFalse);
      expect(harness.active.length, 1); // Only two failures since recovery.
      harness.fire();
      await flush();
      expect(controller.needsResume, isTrue);
      controller.dispose();
    },
  );

  for (final error in [false, true]) {
    for (final manual in [false, true]) {
      test(
        'dispose fences late ${manual ? 'manual grant' : 'send'} ${error ? 'error' : 'success'}',
        () async {
          final backend = Backend();
          final harness = ScheduleHarness();
          final controller = SyncController(
            backend,
            now: () => harness.now,
            schedule: harness.schedule,
          );
          var notifications = 0;
          controller.addListener(() => notifications++);
          Future<void>? pending;
          if (manual) {
            controller.setEnabled(true);
            await flush();
            backend.retrying = Completer<bool>();
            pending = controller.retry(item());
          } else {
            backend.sending = Completer<void>();
            controller.setEnabled(true);
            await flush();
          }
          controller.dispose();
          final before = notifications;
          if (manual) {
            if (error) {
              backend.retrying!.completeError(StateError('late grant'));
            } else {
              backend.retrying!.complete(true);
            }
            await pending;
          } else {
            if (error) {
              backend.sending!.completeError(StateError('late send'));
            } else {
              backend.sending!.complete();
            }
          }
          await flush();
          expect(notifications, before);
          expect(backend.sends, 1);
          expect(controller.items, isEmpty);
          expect(harness.active, isEmpty);
        },
      );
    }
  }

  for (final enableToggle in [false, true]) {
    for (final result in ['null', 'future', 'error']) {
      test('recovery survives ${enableToggle ? 'enable' : 'foreground'} '
          'changes during $result deadline without resetting budget', () async {
        final backend = Backend()..failSend = result != 'error';
        final harness = ScheduleHarness();
        final controller = SyncController(
          backend,
          now: () => harness.now,
          schedule: harness.schedule,
        );
        void toggle(bool value) {
          if (enableToggle) {
            controller.setEnabled(value);
          } else {
            controller.setForeground(value);
          }
        }

        for (var attempt = 1; attempt <= 3; attempt++) {
          backend.nextLookup = Completer<DateTime?>();
          if (attempt == 1) {
            controller.setEnabled(true);
          } else {
            harness.fire();
          }
          await flush();
          // A third send error stops before querying another deadline.
          if (attempt < 3 || result == 'error') {
            expect(controller.busy, isTrue);
            toggle(false);
            toggle(true);
            if (result == 'error') {
              backend.nextLookup!.completeError(StateError('deadline'));
            } else {
              backend.nextLookup!.complete(
                result == 'future'
                    ? harness.now.add(const Duration(minutes: 5))
                    : null,
              );
            }
          }
          await flush();
          await flush();
          expect(backend.sends, attempt);
          expect(
            backend.deadlineQueries,
            attempt == 3 && result != 'error' ? 2 : attempt,
          );
          expect(harness.active.length, attempt < 3 ? 1 : 0);
          if (attempt < 3) {
            final timer = harness.active.single;
            final expected = result == 'future'
                ? const Duration(minutes: 5)
                : const Duration(seconds: 30);
            expect(timer.due.difference(harness.now), expected);
            toggle(false);
            harness.now = harness.now.add(const Duration(seconds: 10));
            toggle(true);
            await flush();
            expect(harness.active.single.due, timer.due);
            timer.action(); // Stale callback must not transmit.
            await flush();
            expect(backend.sends, attempt);
            expect(backend.deadlineQueries, attempt);
          }
        }
        toggle(false);
        toggle(true);
        await controller.wake();
        expect(backend.sends, 3);
        expect(controller.needsResume, isTrue);
        expect(harness.active, isEmpty);
        backend.failSend = false;
        backend.nextLookup = null;
        await controller.resume(); // Only explicit action resets internal stop.
        expect(backend.sends, 4);
        expect(controller.needsResume, isFalse);
        expect(backend.maximumConcurrent, 1);
        expect(harness.maximumActive, 1);
        controller.dispose();
      });
    }
  }

  test(
    'inactive error completion preserves the remaining recovery delay',
    () async {
      final backend = Backend()
        ..failSend = true
        ..nextLookup = Completer<DateTime?>();
      final harness = ScheduleHarness();
      final controller = SyncController(
        backend,
        now: () => harness.now,
        schedule: harness.schedule,
      );
      controller.setEnabled(true);
      await flush();
      controller.setForeground(false);
      backend.nextLookup!.complete(null);
      await flush();
      expect(harness.active, isEmpty);
      harness.now = harness.now.add(const Duration(seconds: 10));
      controller.setForeground(true);
      await flush();
      expect(
        harness.active.single.due.difference(harness.now),
        const Duration(seconds: 20),
      );
      expect(backend.sends, 1);
      expect(backend.deadlineQueries, 1);
      controller.dispose();
    },
  );

  for (final error in [false, true]) {
    test(
      'disposed deadline ${error ? 'failure' : 'result'} cannot publish or schedule',
      () async {
        final backend = Backend()
          ..failSend = true
          ..nextLookup = Completer<DateTime?>();
        final harness = ScheduleHarness();
        final controller = SyncController(
          backend,
          now: () => harness.now,
          schedule: harness.schedule,
        );
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.setEnabled(true);
        await flush();
        controller.dispose();
        final before = notifications;
        if (error) {
          backend.nextLookup!.completeError(StateError('deadline'));
        } else {
          backend.nextLookup!.complete(harness.now);
        }
        await flush();
        expect(notifications, before);
        expect(harness.active, isEmpty);
        expect(controller.items, isEmpty);
        expect(backend.sends, 1);
      },
    );
  }

  test(
    'send and deadline errors retain their combined internal failure count',
    () async {
      final backend = Backend()
        ..failSend = true
        ..failNext = true;
      final harness = ScheduleHarness();
      final controller = SyncController(
        backend,
        now: () => harness.now,
        schedule: harness.schedule,
      );
      controller.setEnabled(true);
      await flush();
      harness.fire();
      await flush();
      expect(backend.sends, 2);
      expect(backend.deadlineQueries, 1);
      expect(controller.needsResume, isTrue);
      expect(harness.active, isEmpty);
      controller.dispose();
    },
  );

  test(
    'queued wake cannot bypass failure delay or the third-failure stop',
    () async {
      final backend = Backend()
        ..failSend = true
        ..sending = Completer<void>();
      final callbacks = <VoidCallback>[];
      final controller = SyncController(
        backend,
        schedule: (delay, action) {
          expect(delay, const Duration(seconds: 30));
          callbacks.add(action);
          return () {};
        },
      );
      controller.setEnabled(true);
      for (var attempt = 1; attempt <= 3; attempt++) {
        await controller.wake(); // Queued while current send is outstanding.
        backend.sending!.complete();
        await flush();
        await flush();
        expect(backend.sends, attempt);
        expect(callbacks.length, attempt < 3 ? attempt : 2);
        if (attempt < 3) {
          backend.sending = Completer<void>();
          callbacks[attempt - 1]();
        }
      }
      expect(controller.message, contains('자동 확인을 잠시 멈췄어요'));
      controller.dispose();
    },
  );

  test(
    'send failure without a persisted deadline gets bounded recovery',
    () async {
      final backend = Backend()..failSend = true;
      final callbacks = <VoidCallback>[];
      final controller = SyncController(
        backend,
        schedule: (delay, action) {
          expect(delay, const Duration(seconds: 30));
          callbacks.add(action);
          return () {};
        },
      );
      controller.setEnabled(true);
      await flush();
      expect(callbacks.length, 1);
      callbacks.first();
      await flush();
      expect(backend.sends, 2);
      expect(callbacks.length, 2);
      controller.dispose();
    },
  );

  test('resume during a rejected manual request is not lost', () async {
    final backend = Backend();
    final controller = SyncController(backend);
    controller.setEnabled(true);
    await flush();
    backend.retrying = Completer<bool>();
    final retry = controller.retry(item());
    controller.setForeground(false);
    controller.setForeground(true);
    backend.retrying!.complete(false);
    await retry;
    await flush();
    expect(backend.sends, 2);
    expect(backend.maximumConcurrent, 1);
    controller.dispose();
  });

  test(
    'late manual deadline lookup cannot install a second timer after resume',
    () async {
      final now = DateTime.utc(2026, 9, 29);
      final backend = Backend()..due = now.add(const Duration(minutes: 1));
      var activeTimers = 0;
      final controller = SyncController(
        backend,
        now: () => now,
        schedule: (delay, action) {
          activeTimers++;
          var canceled = false;
          return () {
            if (!canceled) {
              canceled = true;
              activeTimers--;
            }
          };
        },
      );
      controller.setEnabled(true);
      await flush();
      expect(activeTimers, 1);
      backend.acceptRetry = false;
      backend.nextLookup = Completer<DateTime?>();
      final retry = controller.retry(item());
      await flush();
      expect(controller.busy, isTrue);
      controller.setForeground(false);
      controller.setForeground(true);
      backend.nextLookup!.complete(backend.due);
      await retry;
      await flush();
      expect(activeTimers, 1);
      controller.dispose();
      expect(activeTimers, 0);
    },
  );

  for (final deadlineFailure in [false, true]) {
    test(
      'bounded recovery after ${deadlineFailure ? 'deadline lookup' : 'send'} errors',
      () async {
        final now = DateTime.utc(2026, 9, 29);
        final backend = Backend()
          ..due = now
          ..failSend = !deadlineFailure
          ..failNext = deadlineFailure;
        final callbacks = <VoidCallback>[];
        final controller = SyncController(
          backend,
          now: () => now,
          schedule: (delay, action) {
            expect(delay, const Duration(seconds: 30));
            callbacks.add(action);
            return () {};
          },
        );
        controller.setEnabled(true);
        await flush();
        expect(callbacks.length, 1);
        callbacks[0]();
        await flush();
        expect(callbacks.length, 2);
        callbacks[1]();
        await flush();
        expect(callbacks.length, 2);
        expect(backend.sends, 3);
        expect(controller.message, contains('자동 확인을 잠시 멈췄어요'));
        controller.dispose();
      },
    );
  }

  test(
    'foreground timer waits for the persisted due and pauses without new sends',
    () async {
      final backend = Backend();
      final now = DateTime.utc(2026, 9, 29);
      backend.due = now.add(const Duration(minutes: 5));
      Duration? delay;
      VoidCallback? callback;
      var canceled = false;
      final controller = SyncController(
        backend,
        now: () => now,
        schedule: (d, action) {
          delay = d;
          callback = action;
          return () {
            canceled = true;
          };
        },
      );
      controller.setEnabled(true);
      await flush();
      expect(backend.sends, 1);
      expect(delay, const Duration(minutes: 5));
      controller.setForeground(false);
      expect(canceled, isTrue);
      callback!();
      await flush();
      expect(backend.sends, 1);
      controller.setForeground(true);
      await flush();
      expect(backend.sends, 2);
      controller.dispose();
    },
  );

  test(
    'resume during a running send requests one followup without concurrency',
    () async {
      final backend = Backend()..sending = Completer<void>();
      final controller = SyncController(backend);
      controller.setEnabled(true);
      controller.setEnabled(false);
      controller.setEnabled(true);
      await flush();
      expect(backend.sends, 1);
      backend.sending!.complete();
      await flush();
      await flush();
      expect(backend.sends, 2);
      expect(backend.maximumConcurrent, 1);
      controller.dispose();
    },
  );

  test('disposed account never publishes late loaded rows', () async {
    final backend = Backend()..loading = Completer<List<SyncItem>>();
    final controller = SyncController(backend);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });
    final load = controller.refresh();
    controller.dispose();
    backend.loading!.complete([item()]);
    await load;
    expect(controller.items, isEmpty);
    expect(notifications, 0);
  });

  test(
    'stale manual attempt refreshes without claiming transmission completion',
    () async {
      final backend = Backend()..acceptRetry = false;
      final controller = SyncController(backend);
      controller.setEnabled(true);
      await flush();
      await controller.retry(item());
      expect(backend.retries, 1);
      expect(backend.sends, 1);
      expect(controller.items.single.mutation.state, 'RETRY');
      controller.dispose();
    },
  );

  test('manual retry acceptance wakes the queue but is not an ACK', () async {
    final backend = Backend();
    final controller = SyncController(backend);
    controller.setEnabled(true);
    await flush();
    await controller.retry(item());
    expect(backend.retries, 1);
    expect(backend.sends, 2);
    expect(controller.items.single.mutation.state, 'RETRY');
    controller.dispose();
  });

  testWidgets('explicit resume button restarts a stopped internal recovery', (
    tester,
  ) async {
    final backend = Backend()..failSend = true;
    final harness = ScheduleHarness();
    final controller = SyncController(
      backend,
      now: () => harness.now,
      schedule: harness.schedule,
    );
    controller.setEnabled(true);
    await tester.pump();
    harness.fire();
    await tester.pump();
    harness.fire();
    await tester.pump();
    expect(controller.needsResume, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('전송 다시 시도'), findsOneWidget);
    expect(find.textContaining('자동 전송을 잠시 멈췄어요'), findsOneWidget);
    await tester.tap(find.text('상태 다시 확인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('자동 전송을 잠시 멈췄어요'), findsOneWidget);
    controller.setForeground(false);
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '전송 다시 시도'),
          )
          .onPressed,
      isNull,
    );
    controller.setForeground(true);
    await tester.pump();
    expect(controller.needsResume, isTrue);
    backend.failSend = false;
    await tester.tap(find.text('전송 다시 시도'));
    await tester.pumpAndSettle();
    expect(backend.sends, 4);
    expect(find.text('전송 다시 시도'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('load failure is never displayed as empty or private data', (
    tester,
  ) async {
    final controller = SyncController(Backend()..failLoad = true);
    await tester.pumpWidget(
      MaterialApp(home: SyncScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('확인하지 못했어요'), findsOneWidget);
    expect(find.text('대기 중인 정보가 없어요.'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'retry screen keeps sensitive values out and supports large text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SyncController(Backend());
      controller.setEnabled(true);
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SyncScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('태그'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
