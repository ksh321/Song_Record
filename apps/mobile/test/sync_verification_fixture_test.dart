import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/canonical_conflict_plan.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';

import '../tool/sync_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('installed-app race fixture rejects the first choice and refreshes latest values', () async {
    final root = await Directory.systemTemp.createTemp('sr-canonical-race-');
    final fixture = await SyncVerificationFixture.create(root, canonical: true, changeOnReview: true);
    try {
      final actions = fixture.controller.conflicts! as CanonicalConflictActions;
      final first = await actions.reviewCanonical(fixture.controller.canonicalItems.single.intentId);
      expect(first.server['revision'], 2);
      await expectLater(actions.resolveCanonical(first, ConflictChoice.local), throwsStateError);
      final latest = await actions.reviewCanonical(first.intentId);
      expect(latest.server['revision'], 3);
      await actions.resolveCanonical(latest, ConflictChoice.server);
      expect(await actions.canonicalCandidates(), isEmpty);
      expect(fixture.transport.calls, 0);
    } finally {
      await fixture.close();
      await root.delete(recursive: true);
    }
  });
  test('canonical candidate appears without a conflict queue and stays queued until ACK', () async {
    final root = await Directory.systemTemp.createTemp('sr-canonical-fixture-');
    final gate = Completer<void>();
    final fixture = await SyncVerificationFixture.create(root, canonical: true, responseDelay: () => gate.future);
    try {
      expect(fixture.controller.items, isEmpty);
      expect(fixture.controller.canonicalItems, hasLength(1));
      final actions = fixture.controller.conflicts! as CanonicalConflictActions;
      await actions.resolveCanonical(fixture.controller.canonicalItems.single, ConflictChoice.local);
      await fixture.controller.refresh();
      expect(fixture.controller.canonicalItems.single.state, 'QUEUED');
      final send = fixture.controller.backend.send();
      await fixture.transport.started.future;
      expect((await actions.canonicalCandidates()).single.state, 'QUEUED');
      gate.complete();
      await send;
      await fixture.controller.refresh();
      expect(fixture.controller.canonicalItems, isEmpty);
      expect(fixture.controller.items, isEmpty);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await fixture.close();
      await root.delete(recursive: true);
    }
  });
  for (final status in [401, 403]) {
    test(
      'isolated fixture $status blocks queued lifecycle followup and preserves unrelated files',
      () async {
        final root = await Directory.systemTemp.createTemp('sr-fixture-tests-');
        final untouched = File('${root.path}/unrelated.txt');
        await untouched.writeAsString('preserve');
        final gate = Completer<void>();
        final fixture = await SyncVerificationFixture.create(
          root,
          authenticationStatus: status,
          responseDelay: () => gate.future,
        );
        try {
          final finished = Completer<void>();
          fixture.controller.addListener(() {
            if (fixture.transport.calls == 1 &&
                !fixture.controller.busy &&
                !finished.isCompleted) {
              finished.complete();
            }
          });
          fixture.controller.setEnabled(true);
          // Wait for the actual transport call, never a timer or sleep guess.
          await fixture.transport.started.future.timeout(
            const Duration(seconds: 10),
          );
          final pending = fixture.controller.wake();
          fixture.controller.setForeground(false);
          fixture.controller.setForeground(true);
          gate.complete();
          await pending;
          await finished.future.timeout(const Duration(seconds: 10));
          expect(fixture.transport.calls, 1);
          expect(
            (await fixture.store.pendingMutations()).map((m) => m.attemptCount),
            [1, 0],
          );
          expect(fixture.controller.backend.automaticFollowupAllowed, isFalse);
          // A later lifecycle resume is automatic too, even after the first
          // request has finished. It must not consume the next queued item.
          fixture.controller.setForeground(false);
          fixture.controller.setForeground(true);
          await fixture.controller.wake();
          await fixture.controller.refresh();
          expect(fixture.transport.calls, 1);
          expect(
            (await fixture.store.pendingMutations()).map((m) => m.attemptCount),
            [1, 0],
          );
          expect(await untouched.readAsString(), 'preserve');
        } finally {
          gate.isCompleted ? null : gate.complete();
          await fixture.close();
          expect(
            root.path.split(Platform.pathSeparator).last,
            startsWith('sr-fixture-tests-'),
          );
          await root.delete(recursive: true);
        }
      },
    );
  }
  test(
    'isolated conflict fixture uses real storage and keeps earlier runs',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-fixture-tests-');
      final first = await SyncVerificationFixture.create(root);
      SyncVerificationFixture? second;
      try {
        final old = (await first.store.pendingMutations()).single;
        final review = await first.controller.conflicts!.review(old.opId);
        await first.controller.conflicts!.resolve(review, {
          'name': ConflictChoice.local,
        });
        await first.controller.backend.send();
        expect(first.transport.calls, 1);
        expect(await first.store.pendingWorkMutations(), isEmpty);
        expect(
          jsonDecode(
            (await first.store.readMetadata(
              LocalEntity.tag,
              fixtureId(10),
            ))!.serverJson!,
          )['name'],
          '이 기기 이름',
        );
        second = await SyncVerificationFixture.create(root);
        expect(
          (await second.store.pendingWorkMutations()).single.state,
          'CONFLICT',
        );
        expect(await first.store.pendingWorkMutations(), isEmpty);
        expect((await root.list().toList()).length, 2);
      } finally {
        await second?.close();
        await first.close();
        expect(
          root.path.split(Platform.pathSeparator).last,
          startsWith('sr-fixture-tests-'),
        );
        await root.delete(recursive: true);
      }
    },
  );
}
