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

const owner = '11111111-1111-4111-8111-111111111111',
    rec = '22222222-2222-4222-8222-222222222222',
    op = '33333333-3333-4333-8333-333333333333';
const time = '2026-09-30T00:00:00Z';
Map<String, Object?> snapshot(int revision, String? tier) => {
  'id': rec,
  'revision': revision,
  'updated_at': time,
  'metadata_state': 'SAVED',
  'song_id': null,
  'title_snapshot': 'recording',
  'artist_snapshot': null,
  'version_code': 'NORMAL',
  'key_mode': null,
  'key_shift': null,
  'note': 'preserved',
  'recorded_at': time,
  'timezone_id': 'UTC',
  'timezone_offset_minutes': 0,
  'origin_device_id': owner,
  'link_revision': 1,
  'lifecycle_state': 'ACTIVE',
  'condition_code': null,
  'condition_name_snapshot': null,
  'tier': tier,
  'tag_ids': <String>[],
  'tags': <Object>[],
};
MutationRequest? request(Map<String, Object?> changes) =>
    MutationRequest.prepare(
      QueuedMutation(
        opId: op,
        localOrder: 1,
        entity: LocalEntity.recording,
        entityId: rec,
        operation: LocalOperation.patch,
        state: 'PENDING',
        baseRevision: 1,
        payload: canonicalJson(changes),
        attemptCount: 0,
      ),
    );

class TierTransport implements MutationTransport {
  TierTransport(this.tier);
  final String? tier;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    expect(request.path, '/v1/recordings/$rec/tier');
    expect(jsonDecode(request.body), {'base_revision': 1, 'tier': tier});
    return MutationResponse(200, jsonEncode(snapshot(2, tier)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'dedicated tier route accepts exact enum/null and rejects mixed edits',
    () {
      for (final tier in ['S', 'A', 'B', 'C', 'D', null]) {
        final value = request({'base_revision': 1, 'tier': tier})!;
        expect(value.path, '/v1/recordings/$rec/tier');
        expect(value.method, 'PATCH');
        expect(
          decodeMetadataSnapshot(
            value,
            MutationResponse(200, jsonEncode(snapshot(2, tier))),
          )['tier'],
          tier,
        );
      }
      expect(
        request({'base_revision': 1, 'tier': 'A', 'note': 'mixed'}),
        isNull,
      );
      expect(request({'base_revision': 1, 'tier': 'INVALID'}), isNull);
      expect(request({'base_revision': 0, 'tier': 'A'}), isNull);
      final value = request({'base_revision': 1, 'tier': 'A'})!;
      expect(
        () => decodeMetadataSnapshot(
          value,
          MutationResponse(200, jsonEncode(snapshot(2, 'B'))),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeMetadataSnapshot(
          value,
          MutationResponse(
            200,
            jsonEncode({...snapshot(2, 'A'), 'metadata_state': 'DRAFT'}),
          ),
        ),
        throwsFormatException,
      );
      expect(
        request({'base_revision': 1, 'note': 'ordinary'})!.path,
        '/v1/recordings/$rec',
      );
    },
  );
  for (final tier in ['A', null]) {
    test(
      'tier $tier dispatch acknowledges existing saved recording without audio',
      () async {
        final dir = await Directory.systemTemp.createTemp('sr-tier-dispatch-');
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => dir,
          temporaryDirectory: () async => dir,
        );
        try {
          await manager.openAccount(owner);
          await manager.logout();
          final paths = await AccountPaths.create(
            dir,
            owner,
            AppEnvironment.dev,
          );
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
              jsonEncode(snapshot(1, null)),
              jsonEncode(snapshot(1, null)),
              0,
            ],
          );
          await db.close();
          final store = await manager.openAccount(owner);
          final repo = LocalRepository(store, newId: () => op);
          await repo.save(
            repo.preparePatch(
              entity: LocalEntity.recording,
              entityId: rec,
              baseRevision: 1,
              draft: snapshot(1, tier),
              changes: {'tier': tier},
            ),
          );
          expect(
            await repo.dispatch(
              transport: TierTransport(tier),
              session: () async => AuthSession(
                userId: owner,
                deviceId: owner,
                accessToken: 'synthetic',
                refreshToken: 'unused',
                accessExpiresAt: DateTime.utc(2030),
                refreshExpiresAt: DateTime.utc(2030),
              ),
            ),
            1,
          );
          final copy = (await repo.read(LocalEntity.recording, rec))!;
          expect(copy.revision, 2);
          expect(jsonDecode(copy.serverJson!)['tier'], tier);
          expect(jsonDecode(copy.localJson!)['note'], 'preserved');
          expect(await store.readCursor(), isNull);
          expect(await repo.pending(), isEmpty);
        } finally {
          await manager.logout();
          expect(
            dir.path.split(Platform.pathSeparator).last,
            startsWith('sr-tier-dispatch-'),
          );
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
