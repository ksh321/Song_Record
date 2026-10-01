import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/metadata_response.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'recording_tier_dispatch_test.dart' show owner, rec, op, snapshot;

const song = '44444444-4444-4444-8444-444444444444';

class LinkTransport implements MutationTransport {
  LinkTransport(this.target, this.previous);
  final String? target, previous;
  int calls = 0;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    calls++;
    expect(request.path, '/v1/recordings/$rec/song');
    expect(jsonDecode(request.body), {'base_revision': 1, 'song_id': target});
    return MutationResponse(
      200,
      jsonEncode({
        ...snapshot(2, 'A'),
        'song_id': target,
        'link_revision': target == previous ? 1 : 2,
      }),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'connect',
    'disconnect',
    'same',
    'missing',
    'deleted',
  ]) {
    test('recording link $scenario preserves snapshot and audio', () async {
      final dir = await Directory.systemTemp.createTemp('sr-link-dispatch-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => dir,
        temporaryDirectory: () async => dir,
      );
      final previous = {'disconnect', 'same'}.contains(scenario) ? song : null;
      final target = scenario == 'disconnect' ? null : song;
      final before = {...snapshot(1, 'A'), 'song_id': previous};
      try {
        await manager.openAccount(owner);
        await manager.logout();
        final paths = await AccountPaths.create(dir, owner, AppEnvironment.dev);
        final file = await paths.checkedFile(paths.audioPath(rec));
        await file.writeAsBytes([1, 2, 3, 4], flush: true);
        final db = AccountDatabase(
          NativeDatabase(await paths.databaseFile()),
          userId: owner,
          environment: AppEnvironment.dev,
        );
        await db.verifyReady();
        await db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,?,?,?,?)',
          [
            owner,
            'RECORDING',
            rec,
            1,
            jsonEncode(before),
            jsonEncode(before),
            0,
          ],
        );
        if (scenario != 'missing') {
          await db.customStatement(
            'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,?,?,?,?)',
            [
              owner,
              'SONG',
              song,
              1,
              jsonEncode({'id': song, 'revision': 1}),
              scenario == 'deleted' ? 1 : 0,
              0,
            ],
          );
        }
        await db.close();
        final store = await manager.openAccount(owner);
        final repo = LocalRepository(store, newId: () => op);
        await repo.save(
          repo.preparePatch(
            entity: LocalEntity.recording,
            entityId: rec,
            baseRevision: 1,
            draft: {...before, 'song_id': target},
            changes: {'song_id': target},
          ),
        );
        final transport = LinkTransport(target, previous);
        final count = await repo.dispatch(
          transport: transport,
          session: () async => AuthSession(
            userId: owner,
            deviceId: owner,
            accessToken: 'synthetic',
            refreshToken: 'unused',
            accessExpiresAt: DateTime.utc(2030),
            refreshExpiresAt: DateTime.utc(2030),
          ),
        );
        final blocked = {'missing', 'deleted'}.contains(scenario);
        expect(count, blocked ? 0 : 1);
        expect(transport.calls, blocked ? 0 : 1);
        final copy = (await repo.read(LocalEntity.recording, rec))!;
        expect(copy.revision, blocked ? 1 : 2);
        expect(jsonDecode(copy.localJson!)['title_snapshot'], 'recording');
        expect(jsonDecode(copy.localJson!)['note'], 'preserved');
        expect(await file.readAsBytes(), [1, 2, 3, 4]);
        expect(await store.readCursor(), isNull);
        if (blocked) {
          expect((await repo.pending()).single.attemptCount, 0);
        }
      } finally {
        await manager.logout();
        expect(
          dir.path.split(Platform.pathSeparator).last,
          startsWith('sr-link-dispatch-'),
        );
        await dir.delete(recursive: true);
      }
    });
  }
  test(
    'link success rejects changed historical fields, target or link revision',
    () {
      MutationRequest? make(Map<String, Object?> body) =>
          MutationRequest.prepare(
            QueuedMutation(
              opId: op,
              localOrder: 1,
              entity: LocalEntity.recording,
              entityId: rec,
              operation: LocalOperation.patch,
              state: 'PENDING',
              baseRevision: 1,
              basePayload: jsonEncode(snapshot(1, 'A')),
              payload: jsonEncode(body),
              attemptCount: 0,
            ),
          );
      final request = make({'base_revision': 1, 'song_id': song})!;
      final valid = {...snapshot(2, 'A'), 'song_id': song, 'link_revision': 2};
      for (final overrides in [
        {'song_id': null},
        {'link_revision': 1},
        {'title_snapshot': 'changed'},
        {'tier': 'B'},
      ]) {
        expect(
          () => decodeMetadataSnapshot(
            request,
            MutationResponse(200, jsonEncode({...valid, ...overrides})),
          ),
          throwsFormatException,
        );
      }
      expect(
        make({'base_revision': 1, 'song_id': song, 'note': 'mixed'}),
        isNull,
      );
      expect(make({'base_revision': 1, 'song_id': 'invalid'}), isNull);
      expect(make({'base_revision': 1, 'song_id': 42}), isNull);
    },
  );
}
