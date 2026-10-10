import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

const owner = '00000000-0000-4000-8000-000000001801';
const other = '00000000-0000-4000-8000-000000001802';
const rec = '00000000-0000-4000-8000-000000001810';
final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
Map<String, dynamic> spec() => {
  'sha256': sha256.convert(bytes).toString(),
  'size_bytes': bytes.length,
  'duration_ms': 12000,
  'codec': 'AAC_LC',
  'sample_rate': 48000,
  'channels': 1,
  'capture_integrity': 'VALIDATED',
};
Future<void> capture(LocalRepository repo, {String? scope, Uint8List? data}) =>
    repo.importCompletedCapture(
      accountScope: scope ?? 'dev/$owner',
      recordingId: rec,
      bytes: data ?? bytes,
      fileSpec: spec(),
      recordedAt: DateTime.utc(2026, 10, 10, 1, 2, 3),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    );

class _DraftTransport implements MutationTransport {
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    return MutationResponse(
      201,
      jsonEncode({
        ...body,
        'origin_device_id': owner,
        'revision': 1,
        'link_revision': 1,
        'lifecycle_state': 'ACTIVE',
        'updated_at': '2026-10-10T01:02:03.000Z',
        'tier': null,
        'condition_code': null,
        'condition_name_snapshot': null,
      }),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('capture atomically keeps verified original, DRAFT and a sendable metadata queue after reopen', () async {
    final root = await Directory.systemTemp.createTemp('sr-capture-');
    final m = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () => Future.value(root),
      temporaryDirectory: () => Future.value(root),
    );
    try {
      var store = await m.openAccount(owner);
      var repo = LocalRepository(store);
      await capture(repo);
      await capture(repo);
      expect(await store.readLocalAudio(rec), bytes);
      expect((await repo.pending()).length, 1);
      final request = MutationRequest.prepare((await repo.pending()).single)!;
      expect(request.path, '/v1/recordings');
      expect(jsonDecode(request.body)['metadata_state'], 'DRAFT');
      expect(jsonDecode(request.body).containsKey('file'), false);
      final sent = await repo.dispatch(
        transport: _DraftTransport(),
        session: () async => AuthSession(
          userId: owner,
          deviceId: owner,
          accessToken: 'synthetic',
          refreshToken: 'unused',
          accessExpiresAt: DateTime.utc(2030),
          refreshExpiresAt: DateTime.utc(2030),
        ),
      );
      expect(sent, 1);
      expect((await repo.pendingRecordings()).single['file'], spec());
      await m.logout();
      store = await m.openAccount(owner);
      repo = LocalRepository(store);
      final row = (await repo.pendingRecordings()).single;
      expect(row['id'], rec);
      expect(row['timezone_id'], 'Asia/Seoul');
      expect(row['timezone_offset_minutes'], 540);
      expect(row['recorded_at'], '2026-10-10T01:02:03.000Z');
      expect(row['file'], spec());
      expect(await store.readLocalAudio(rec), bytes);
      await capture(repo);
      expect(await repo.pending(), isEmpty);
    } finally {
      await m.logout();
      await root.delete(recursive: true);
    }
  });
  test(
    'recovery does not overwrite later input or regress a SAVED record',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-capture-edit-');
      final m = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () => Future.value(root),
        temporaryDirectory: () => Future.value(root),
      );
      try {
        final repo = LocalRepository(await m.openAccount(owner));
        await capture(repo);
        final initial = jsonDecode(
          (await repo.read(LocalEntity.recording, rec))!.localJson!,
        ) as Map<String, dynamic>;
        initial.remove('user_id');
        await repo.save(
          repo.preparePatch(
            entity: LocalEntity.recording,
            entityId: rec,
            baseRevision: 0,
            draft: {
              ...initial,
              'title_snapshot': 'keep my input',
              'metadata_state': 'SAVED',
            },
            changes: {'title_snapshot': 'keep my input'},
          ),
        );
        await capture(repo);
        final current = jsonDecode(
          (await repo.read(LocalEntity.recording, rec))!.localJson!,
        );
        expect(current['title_snapshot'], 'keep my input');
        expect(current['metadata_state'], 'SAVED');
        expect((await repo.pending()).length, 2);
        expect(await repo.pendingRecordings(), isEmpty);
      } finally {
        await m.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'foreign scope, checksum mismatch and expired account never create a draft',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-capture-fence-');
      final m = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () => Future.value(root),
        temporaryDirectory: () => Future.value(root),
      );
      try {
        final repo = LocalRepository(await m.openAccount(owner));
        await expectLater(
          capture(repo, scope: 'dev/$other'),
          throwsFormatException,
        );
        await expectLater(
          capture(repo, data: Uint8List.fromList([9, 9, 9, 9, 9])),
          throwsFormatException,
        );
        expect(await repo.pendingRecordings(), isEmpty);
        expect(await repo.pending(), isEmpty);
        final stale = capture(repo);
        final next = m.openAccount(other);
        await expectLater(stale, throwsStateError);
        final b = LocalRepository(await next);
        expect(await b.pendingRecordings(), isEmpty);
        expect(await b.pending(), isEmpty);
      } finally {
        await m.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test('queue failure rolls back all DB records and retry never replaces existing immutable intent', () async {
    final root = await Directory.systemTemp.createTemp('sr-capture-rollback-');
    final m = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () => Future.value(root),
      temporaryDirectory: () => Future.value(root),
    );
    try {
      final store = await m.openAccount(owner);
      final repo = LocalRepository(store);
      await repo.save(
        LocalEdit(
          opId: rec,
          entity: LocalEntity.song,
          entityId: other,
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: {'id': other, 'title': 'original'},
          changes: {'id': other, 'title': 'original'},
        ),
      );
      await expectLater(capture(repo), throwsStateError);
      expect(await repo.read(LocalEntity.recording, rec), isNull);
      expect(await repo.pendingRecordings(), isEmpty);
      expect((await repo.pending()).length, 1);
      await expectLater(store.readLocalAudio(rec), throwsStateError);
      expect(
        jsonDecode((await repo.pending()).single.payload)['title'],
        'original',
      );
    } finally {
      await m.logout();
      await root.delete(recursive: true);
    }
  });
}
