import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';

import '../tool/sync_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
