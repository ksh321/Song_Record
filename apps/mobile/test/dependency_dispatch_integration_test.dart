import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'metadata_dispatcher_test.dart' show FakeTransport;
import 'metadata_followup_dispatch_test.dart' show baseline, id;
import 'recording_save_dispatch_test.dart' show draft;
import 'recording_tier_dispatch_test.dart' show owner, rec;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed song holds recording across restart while independent tag sends',
    () async {
      final dir = await Directory.systemTemp.createTemp('sr-dependency-flow-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => dir,
        temporaryDirectory: () async => dir,
      );
      try {
        var store = await manager.openAccount(owner);
        var repo = LocalRepository(store);
        final audio = File('${dir.path}/synthetic-audio.bin');
        await audio.writeAsBytes([4, 3, 2, 1]);
        final song = repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: id(10),
          draft: baseline(LocalEntity.song, id(10)),
          changes: {
            'source_type': 'MANUAL',
            'title': 'before',
            'artist': 'artist',
            'manual_reason': 'TJ_NOT_FOUND',
            'version_code': 'NORMAL',
            'note': '',
          },
        );
        await repo.save(song);
        final value = {...draft(), 'song_id': id(10)};
        final fields = Map<String, Object?>.from(value)
          ..removeWhere(
            (key, _) => {
              'revision',
              'updated_at',
              'origin_device_id',
              'link_revision',
              'lifecycle_state',
              'condition_name_snapshot',
            }.contains(key),
          );
        final recording = repo.prepareCreate(
          entity: LocalEntity.recording,
          entityId: rec,
          draft: value,
          changes: fields,
        );
        await repo.save(recording);
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.tag,
            entityId: id(40),
            draft: {'name': 'before'},
            changes: {'name': 'before'},
          ),
        );
        final sent = <LocalEntity>[];
        var failSong = true;
        final transport = FakeTransport((request) async {
          sent.add(request.mutation.entity);
          if (request.mutation.entity == LocalEntity.song) {
            if (failSong) {
              return const MutationResponse(
                503,
                '{"error":{"code":"TEMPORARY"}}',
              );
            }
            return MutationResponse(
              201,
              jsonEncode({
                'created': true,
                'canonical_song_id': id(10),
                'song': baseline(LocalEntity.song, id(10)),
              }),
            );
          }
          return MutationResponse(
            201,
            jsonEncode(
              request.mutation.entity == LocalEntity.tag
                  ? baseline(LocalEntity.tag, id(40))
                  : value,
            ),
          );
        });
        Future<AuthSession> session() async => AuthSession(
          userId: owner,
          deviceId: owner,
          accessToken: 'synthetic',
          refreshToken: 'unused',
          accessExpiresAt: DateTime.utc(2030),
          refreshExpiresAt: DateTime.utc(2030),
        );
        expect(await repo.dispatch(transport: transport, session: session), 1);
        expect(sent, [LocalEntity.song, LocalEntity.tag]);
        final original = (await repo.pending()).singleWhere(
          (m) => m.opId == recording.opId,
        );
        expect(original.attemptCount, 0);
        await manager.logout();
        store = await manager.openAccount(owner);
        repo = LocalRepository(store);
        expect(await store.claimMutation(), isNull);
        failSong = false;
        expect(await repo.retryMutation(song.opId, expectedAttempt: 1), isTrue);
        expect(await repo.dispatch(transport: transport, session: session), 2);
        expect(sent, [
          LocalEntity.song,
          LocalEntity.tag,
          LocalEntity.song,
          LocalEntity.recording,
        ]);
        final exported = jsonDecode(await store.recoveryData()) as Map;
        final after = ((exported['tables'] as Map)['local_mutations'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((m) => m['op_id'] == recording.opId);
        expect(after['payload'], original.payload);
        expect(after['entity_id'], rec);
        expect(after['queue_state'], 'ACKED');
        expect(await audio.readAsBytes(), [4, 3, 2, 1]);
        expect(await repo.pendingWork(), isEmpty);
      } finally {
        await manager.logout();
        await dir.delete(recursive: true);
      }
    },
  );
}
