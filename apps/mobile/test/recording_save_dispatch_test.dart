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
import 'package:song_record/core/sync/metadata_conflict.dart';
import 'package:song_record/core/sync/metadata_response.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'recording_tier_dispatch_test.dart' show owner, rec, op, snapshot;

Map<String, Object?> fileSpec() => {
  'sha256': List.filled(64, 'a').join(),
  'size_bytes': 100,
  'duration_ms': 1000,
  'codec': 'AAC_LC',
  'sample_rate': 48000,
  'channels': 1,
  'capture_integrity': 'VALIDATED',
};
Map<String, Object?> draft() => {
  ...snapshot(1, null),
  'metadata_state': 'DRAFT',
  'artist_snapshot': 'artist',
  'key_mode': 'ORIGINAL',
  'key_shift': 0,
}..removeWhere((key, _) => {'tier', 'tags', 'tag_ids'}.contains(key));
Map<String, Object?> body() => {
  'base_revision': 1,
  'metadata_state': 'SAVED',
  'file': fileSpec(),
};
MutationRequest? request(Map<String, Object?> payload, {int revision = 1}) =>
    MutationRequest.prepare(
      QueuedMutation(
        opId: op,
        localOrder: 1,
        entity: LocalEntity.recording,
        entityId: rec,
        operation: LocalOperation.patch,
        state: 'PENDING',
        baseRevision: revision,
        payload: jsonEncode(payload),
        basePayload: jsonEncode(draft()),
        attemptCount: 0,
      ),
    );
Map<String, Object?> saved() => {
  ...draft(),
  'revision': 2,
  'metadata_state': 'SAVED',
  'file': fileSpec(),
};

class SaveTransport implements MutationTransport {
  int calls = 0;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    calls++;
    expect(request.mutation.opId, op);
    expect(request.path, '/v1/recordings/$rec');
    expect(jsonDecode(request.body), body());
    return MutationResponse(200, jsonEncode(saved()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('save response omission preserves prior tag names and tier', () {
    final before = {
      ...draft(),
      'tier': null,
      'tag_ids': [op],
      'tags': [
        {'id': op, 'name_snapshot': 'old name'},
      ],
    };
    final wire = MutationRequest.prepare(
      QueuedMutation(
        opId: op,
        localOrder: 1,
        entity: LocalEntity.recording,
        entityId: rec,
        operation: LocalOperation.patch,
        state: 'PENDING',
        baseRevision: 1,
        payload: jsonEncode(body()),
        basePayload: jsonEncode(before),
        attemptCount: 0,
      ),
    )!;
    final result = decodeMetadataSnapshot(
      wire,
      MutationResponse(200, jsonEncode(saved())),
    );
    expect(result['tags'], before['tags']);
    expect(result['tag_ids'], [op]);
    expect(result.containsKey('tier'), isTrue);
    expect(
      () => decodeMetadataSnapshot(
        wire,
        MutationResponse(200, jsonEncode({...saved(), 'tier': 'A'})),
      ),
      throwsFormatException,
    );
  });
  test('save transition never enters generic metadata conflict rebasing', () {
    final mutation = QueuedMutation(
      opId: op,
      localOrder: 1,
      entity: LocalEntity.recording,
      entityId: rec,
      operation: LocalOperation.patch,
      state: 'CONFLICT',
      baseRevision: 1,
      payload: jsonEncode(body()),
      basePayload: jsonEncode(draft()),
      serverResponse: jsonEncode({
        'code': 'REVISION_CONFLICT',
        'status': 409,
        'current': {...draft(), 'revision': 2},
      }),
      attemptCount: 1,
    );
    expect(compareMetadataConflict(mutation), isNull);
  });
  test('save acknowledgement checks normalized requested metadata', () {
    final wire = request({
      ...body(),
      'artist_snapshot': '  new artist  ',
      'note': 'new\r\nnote',
    })!;
    final reply = {
      ...saved(),
      'artist_snapshot': 'new artist',
      'note': 'new\nnote',
    };
    expect(
      decodeMetadataSnapshot(
        wire,
        MutationResponse(200, jsonEncode(reply)),
      )['note'],
      'new\nnote',
    );
    expect(
      () => decodeMetadataSnapshot(
        wire,
        MutationResponse(200, jsonEncode({...reply, 'note': 'wrong'})),
      ),
      throwsFormatException,
    );
  });
  test(
    'save receipt and file survive account restart without advancing cursor',
    () async {
      final dir = await Directory.systemTemp.createTemp('sr-save-dispatch-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => dir,
        temporaryDirectory: () async => dir,
      );
      AccountDatabase? raw;
      try {
        await manager.openAccount(owner);
        await manager.logout();
        final paths = await AccountPaths.create(dir, owner, AppEnvironment.dev);
        final file = await paths.checkedFile(paths.audioPath(rec));
        await file.writeAsBytes([1, 2, 3, 4], flush: true);
        raw = AccountDatabase(
          NativeDatabase(await paths.databaseFile()),
          userId: owner,
          environment: AppEnvironment.dev,
        );
        await raw.verifyReady();
        await raw.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,?,?,?,?)',
          [
            owner,
            'RECORDING',
            rec,
            1,
            jsonEncode(draft()),
            jsonEncode(draft()),
            0,
          ],
        );
        await raw.close();
        raw = null;
        final store = await manager.openAccount(owner);
        final repo = LocalRepository(store, newId: () => op);
        final changes = body()..remove('base_revision');
        await repo.save(
          repo.preparePatch(
            entity: LocalEntity.recording,
            entityId: rec,
            baseRevision: 1,
            draft: {...draft(), ...changes},
            changes: changes,
          ),
        );
        final transport = SaveTransport();
        expect(
          await repo.dispatch(
            transport: transport,
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
        expect(transport.calls, 1);
        expect(await repo.pending(), isEmpty);
        expect(await store.readCursor(), isNull);
        await manager.logout();
        final reopened = await manager.openAccount(owner);
        final copy = (await reopened.readMetadata(LocalEntity.recording, rec))!;
        expect(copy.revision, 2);
        expect(jsonDecode(copy.serverJson!)['file'], fileSpec());
        expect(jsonDecode(copy.localJson!)['metadata_state'], 'SAVED');
        expect(await file.readAsBytes(), [1, 2, 3, 4]);
        expect(await reopened.readCursor(), isNull);
      } finally {
        await raw?.close();
        await manager.logout();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'save sends exact original file metadata, accepts actual save API shape',
    () {
      final payload = body();
      final wire = request(payload)!;
      expect(wire.path, '/v1/recordings/$rec');
      expect(wire.method, 'PATCH');
      expect(wire.body, jsonEncode(payload));
      final result = decodeMetadataSnapshot(
        wire,
        MutationResponse(200, jsonEncode(saved())),
      );
      expect(result['metadata_state'], 'SAVED');
      expect(result['file'], fileSpec());
      expect(result.containsKey('tier'), isFalse);
    },
  );
  test('save rejects unresolved baseline, mixed routes and invalid file specifications', () {
    expect(request({...body(), 'base_revision': 0}, revision: 0), isNull);
    for (final extra in ['song_id', 'tier', 'tag_ids']) {
      expect(request({...body(), extra: null}), isNull);
    }
    for (final invalid in [
      {'size_bytes': 0},
      {'size_bytes': 6291457},
      {'duration_ms': 361001},
      {'sha256': 'wrong'},
      {'sample_rate': 48000.0},
      {'channels': 2},
      {'codec': 'MP3'},
      {'capture_integrity': 'CORRUPT'},
      {'extra': true},
    ]) {
      expect(
        request({
          ...body(),
          'file': {...fileSpec(), ...invalid},
        }),
        isNull,
      );
    }
  });
  test(
    'save acknowledgement rejects different file, state, identity and history',
    () {
      final wire = request(body())!;
      for (final invalid in [
        {
          'file': {...fileSpec(), 'size_bytes': 101},
        },
        {'file': null},
        {'metadata_state': 'DRAFT'},
        {'revision': 3},
        {'id': op},
        {'artist_snapshot': null},
        {'key_mode': null},
        {'note': 'lost'},
        {'link_revision': 2},
        {'song_id': op},
        {'condition_code': 'BAD'},
        {'recorded_at': '2026-10-01T00:00:00Z'},
      ]) {
        expect(
          () => decodeMetadataSnapshot(
            wire,
            MutationResponse(200, jsonEncode({...saved(), ...invalid})),
          ),
          throwsFormatException,
        );
      }
      final missingCondition = saved()..remove('condition_code');
      expect(
        () => decodeMetadataSnapshot(
          wire,
          MutationResponse(200, jsonEncode(missingCondition)),
        ),
        throwsFormatException,
      );
    },
  );
}
