import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/canonical_conflict_plan.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import '../tool/sync_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final boundary in [1, 2, 4, 7, 40]) {
    test('saved resync run reopens without reseeding at boundary $boundary', () async {
      final root = await Directory.systemTemp.createTemp('sr-resync-reopen-');
      var now = DateTime.now().toUtc();
      var fixture = await SyncVerificationFixture.create(root,
        resync: true, expirePage: true, clock: () => now,
        responseDelay: () async {});
      Future<Object?> tables() async =>
        (jsonDecode(await fixture.store.recoveryData()) as Map<String, dynamic>)['tables'];
      try {
        final original = (await fixture.store.pendingWorkMutations()).single;
        for (var step = 0; step < boundary; step++) {
          await fixture.controller.backend.send();
          now = now.add(const Duration(seconds: 6));
        }
        final name = fixture.runName;
        expect(await SyncVerificationFixture.savedRuns(root), [name]);
        await expectLater(SyncVerificationFixture.create(root, resumeRun: '../$name'),
          throwsStateError);
        final retained = await tables();
        final resume = await fixture.store.readSnapshotResume();
        final records = <String, String>{};
        await for (final entry in fixture.run.list()) {
          if (entry is File && entry.path.endsWith('.json')) {
            records[entry.path] = await entry.readAsString();
          }
        }
        await fixture.close();
        // Local expiry during process shutdown must restart, not renew the token.
        if (boundary == 4) now = now.add(const Duration(minutes: 31));
        fixture = await SyncVerificationFixture.create(root, resumeRun: name,
          clock: () => now, responseDelay: () async {});
        expect(fixture.runName, name);
        expect(await tables(), retained);
        expect(await fixture.store.readSnapshotResume(), resume);
        for (final record in records.entries) {
          expect(await File(record.key).readAsString(), record.value);
        }
        for (var step = 0; step < 65; step++) {
          await fixture.controller.backend.send();
          now = now.add(const Duration(seconds: 6));
          if (await fixture.store.readCursor() == 10 &&
              await fixture.store.hasCompleteBaseline()) {
            break;
          }
        }
        expect(await fixture.store.readCursor(), 10);
        expect(await fixture.store.hasCompleteBaseline(), isTrue);
        expect(fixture.transport.calls, 0);
        final actions = fixture.controller.conflicts!;
        final review = await actions.review(original.opId);
        expect(review.server['revision'], 3);
        expect(review.mutation.payload, original.payload);
        await actions.resolve(review, {'name': ConflictChoice.local});
        await fixture.controller.backend.send();
        expect(fixture.transport.calls, 1);
        expect(await fixture.store.pendingWorkMutations(), isEmpty);
        final completed = await tables();
        await fixture.close();
        fixture = await SyncVerificationFixture.create(root, resumeRun: name,
          clock: () => now, responseDelay: () async {});
        expect(await tables(), completed);
        expect(await fixture.store.pendingWorkMutations(), isEmpty);
        expect(await SyncVerificationFixture.savedRuns(root), [name]);
      } finally { await fixture.close(); await root.delete(recursive: true); }
    });
  }
  test('synthetic server restores lost create response, page expiry and partial writes', () async {
    final root = await Directory.systemTemp.createTemp('sr-resync-server-');
    var now = DateTime.now().toUtc();
    final owner = fixtureId(1);
    final auth = AuthSession(userId: owner, deviceId: fixtureId(2),
      accessToken: 'synthetic-only', refreshToken: 'synthetic-only',
      accessExpiresAt: DateTime.utc(2099), refreshExpiresAt: DateTime.utc(2099));
    Future<VerificationSnapshots> reopen() => VerificationSnapshots.open(
      root, owner, () => now, expirePage: true, restoring: true);
    try {
      var server = await VerificationSnapshots.open(root, owner, () => now, expirePage: true);
      final create = SnapshotHttpRequest.create(fixtureId(300));
      var fences = 0;
      // Response lost after the server publishes its durable idempotency record.
      await expectLater(server.send(create, auth, () {
        if (++fences == 2) throw StateError('response lost');
      }), throwsStateError);
      server = await reopen();
      final response = await server.send(create, auth, () {});
      final token = (jsonDecode(response.body) as Map)['snapshot_token'] as String;
      final manifest = await server.send(SnapshotHttpRequest.status(token), auth, () {});
      for (var i = 0; i < 3; i++) {
        expect((await server.send(SnapshotHttpRequest.page(token, 'TAG'), auth, () {})).status, 200);
      }
      final partial = File('${root.path}/interrupted.pending');
      await partial.writeAsString('{"operations":', flush: true);
      server = await reopen();
      expect((await server.send(create, auth, () {})).body, response.body);
      expect((await server.send(SnapshotHttpRequest.status(token), auth, () {})).body, manifest.body);
      expect((await server.send(SnapshotHttpRequest.page(token, 'TAG'), auth, () {})).status, 410);
      server = await reopen();
      expect((await server.send(SnapshotHttpRequest.status(token), auth, () {})).status, 410);
      expect((await server.send(create, auth, () {})).body, response.body);
      final fresh = await server.send(SnapshotHttpRequest.create(fixtureId(301)), auth, () {});
      final freshToken = (jsonDecode(fresh.body) as Map)['snapshot_token'] as String;
      expect(freshToken, isNot(token));
      expect((await server.send(SnapshotHttpRequest.page(freshToken, 'TAG'), auth, () {})).status, 200);
      now = now.add(const Duration(minutes: 31));
      server = await reopen();
      expect((await server.send(SnapshotHttpRequest.status(freshToken), auth, () {})).status, 410);
      expect(await partial.readAsString(), '{"operations":');
      await expectLater(VerificationSnapshots.open(root, fixtureId(999), () => now,
        expirePage: true, restoring: true), throwsStateError);
    } finally { await root.delete(recursive: true); }
  });
  for (final expiry in [false, true]) {
    test('resync verification fixture preserves conflict and reviews fresh values, page expiry=$expiry', () async {
      final root = await Directory.systemTemp.createTemp('sr-resync-fixture-');
      var now = DateTime.now().toUtc();
      final fixture = await SyncVerificationFixture.create(root,
        resync: true, expirePage: expiry, clock: () => now,
        responseDelay: () async {});
      try {
        final original = (await fixture.store.pendingWorkMutations()).single;
        final actions = fixture.controller.conflicts!;
        for (var step = 0; step < 60; step++) {
          await fixture.controller.backend.send();
          now = now.add(const Duration(seconds: 6));
          if (await fixture.store.readCursor() == 10 && await fixture.store.hasCompleteBaseline()) break;
        }
        expect(await fixture.store.readCursor(), 10);
        expect(fixture.transport.calls, 0);
        final review = await actions.review(original.opId);
        expect(review.server['revision'], 3);
        expect(review.server['name'], '재수신한 서버 이름');
        expect(review.mutation.payload, original.payload);
        await actions.resolve(review, {'name': ConflictChoice.local});
        await fixture.controller.backend.send();
        expect(fixture.transport.calls, 1);
        expect(await fixture.store.pendingWorkMutations(), isEmpty);
      } finally { await fixture.close(); await root.delete(recursive: true); }
    });
  }
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
