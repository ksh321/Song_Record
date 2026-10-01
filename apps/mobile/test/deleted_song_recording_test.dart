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
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/sync_controller.dart';

import 'recording_tier_dispatch_test.dart' show owner, rec, op, snapshot;

const deletedSong = '44444444-4444-4444-8444-444444444444';

class DeletedSongTransport implements MutationTransport {
  final requests = <MutationRequest>[];
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    requests.add(request);
    expect(request.path, '/v1/recordings');
    expect(jsonDecode(request.body)['song_id'], deletedSong);
    return MutationResponse(
      201,
      jsonEncode({
        ...snapshot(1, null),
        'metadata_state': 'DRAFT',
        'song_id': null,
      }),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final localDeleted in [false, true]) {
    test(
      'server unlinks deleted song with local deletion known=$localDeleted, preserving wire and file',
      () async {
        final dir = await Directory.systemTemp.createTemp('sr-deleted-song-');
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => dir,
          temporaryDirectory: () async => dir,
        );
        AccountDatabase? rawConnection;
        try {
          await manager.openAccount(owner);
          await manager.logout();
          final paths = await AccountPaths.create(
            dir,
            owner,
            AppEnvironment.dev,
          );
          final audio = await paths.checkedFile(paths.audioPath(rec));
          await audio.writeAsBytes([1, 2, 3, 4], flush: true);
          Future<AccountDatabase> openRaw() async {
            final db = AccountDatabase(
              NativeDatabase(await paths.databaseFile()),
              userId: owner,
              environment: AppEnvironment.dev,
            );
            rawConnection = db;
            await db.verifyReady();
            return db;
          }

          var db = await openRaw();
          await db.customStatement(
            "INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,'SONG',?,3,?,?,0)",
            [
              owner,
              deletedSong,
              jsonEncode({'id': deletedSong, 'revision': 3}),
              localDeleted ? 1 : 0,
            ],
          );
          await db.customStatement(
            "INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at) VALUES(?,?,?, ?,4,'SAVED',0,0)",
            [rec, owner, 'audio/$rec.m4a', 'a' * 64],
          );
          final fileBefore =
              (await db
                      .customSelect('SELECT * FROM local_recording_files')
                      .getSingle())
                  .data;
          await db.close();
          rawConnection = null;
          var store = await manager.openAccount(owner);
          var repo = LocalRepository(store, newId: () => op);
          final body = <String, Object?>{
            'metadata_state': 'DRAFT',
            'song_id': deletedSong,
            'title_snapshot': 'recording',
            'artist_snapshot': null,
            'version_code': 'NORMAL',
            'key_mode': null,
            'key_shift': null,
            'note': 'preserved',
            'recorded_at': '2026-09-30T00:00:00Z',
            'timezone_id': 'UTC',
            'timezone_offset_minutes': 0,
          };
          final edit = repo.prepareCreate(
            entity: LocalEntity.recording,
            entityId: rec,
            draft: body,
            changes: body,
          );
          await repo.save(edit);
          final original = (await repo.pending()).single;
          final transport = DeletedSongTransport();
          Future<AuthSession> session() async => AuthSession(
            userId: owner,
            deviceId: owner,
            accessToken: 'synthetic',
            refreshToken: 'unused',
            accessExpiresAt: DateTime.utc(2030),
            refreshExpiresAt: DateTime.utc(2030),
          );
          final backend = RepositorySyncBackend(repo, transport, session);
          await backend.load();
          expect(backend.statusMessage, isNull);
          await backend.send();
          await backend.load();
          expect(backend.statusMessage, contains('새 녹음 1개를 미연결로 보존'));
          expect(transport.requests.single.mutation.opId, op);
          expect(transport.requests.single.body, original.payload);
          expect(transport.requests.single.attempt, 1);
          expect(await repo.pending(), isEmpty);
          final copy = (await repo.read(LocalEntity.recording, rec))!;
          expect(jsonDecode(copy.localJson!)['song_id'], isNull);
          expect(jsonDecode(copy.localJson!)['note'], 'preserved');
          expect(await audio.readAsBytes(), [1, 2, 3, 4]);
          await manager.logout();
          db = await openRaw();
          expect(
            (await db
                    .customSelect('SELECT * FROM local_recording_files')
                    .getSingle())
                .data,
            fileBefore,
          );
          final saved =
              (await db
                      .customSelect('SELECT * FROM local_mutations')
                      .getSingle())
                  .data;
          expect(saved['op_id'], op);
          expect(saved['payload'], original.payload);
          expect(saved['attempt_count'], 1);
          expect(saved['queue_state'], 'ACKED');
          expect(
            (await db
                    .customSelect(
                      'SELECT body_json FROM mutation_wire_requests',
                    )
                    .getSingle())
                .read<String>('body_json'),
            original.payload,
          );
          await db.close();
          rawConnection = null;
          store = await manager.openAccount(owner);
          repo = LocalRepository(store);
          expect(await repo.unlinkedOfflineRecordingCount(), 1);
          await manager.logout();
          db = await openRaw();
          await db.customStatement(
            "UPDATE metadata_copies SET server_payload=json_set(server_payload,'\u0024.song_id',?) WHERE entity_type='RECORDING' AND entity_id=?",
            [deletedSong, rec],
          );
          await db.close();
          rawConnection = null;
          store = await manager.openAccount(owner);
          expect(await store.unlinkedOfflineRecordingCount(), 0);
        } finally {
          await rawConnection?.close();
          await manager.logout();
          expect(
            dir.path.split(Platform.pathSeparator).last,
            startsWith('sr-deleted-song-'),
          );
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
