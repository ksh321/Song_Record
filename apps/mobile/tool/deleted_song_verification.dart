import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/sync_controller.dart';

import 'sync_verification_fixture.dart';

// Only the isolated debug verification entry imports this synthetic scenario.
final class DeletedRecordingTransport implements MutationTransport {
  DeletedRecordingTransport(this.recording, this.file);
  final Map<String, Object?> recording, file;
  final requests = <MutationRequest>[];
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    if (request.mutation.entity != LocalEntity.recording) {
      throw StateError('Deleted song must never be sent');
    }
    requests.add(request);
    return MutationResponse(
      request.method == 'POST' ? 201 : 200,
      jsonEncode({
        ...recording,
        'song_id': null,
        'metadata_state': request.method == 'POST' ? 'DRAFT' : 'SAVED',
        'revision': request.method == 'POST' ? 1 : 2,
        'updated_at': '2026-10-01T00:00:00Z',
        'origin_device_id': fixtureId(2),
        'link_revision': 1,
        'lifecycle_state': 'ACTIVE',
        'condition_code': null,
        'condition_name_snapshot': null,
        'tier': null,
        'tag_ids': <String>[],
        'tags': <Object>[],
        if (request.method == 'PATCH') 'file': file,
      }),
    );
  }
}

Future<Map<String, bool>> verifyDeletedSong(Directory root) async {
  await root.create(recursive: true);
  final run = await root.createTemp('deleted-song-');
  final owner = fixtureId(1), song = fixtureId(20), rec = fixtureId(30);
  final token = fixtureId(80);
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => run,
    temporaryDirectory: () async => run,
  );
  try {
    var store = await manager.openAccount(owner);
    await installVerificationSnapshot(
      store,
      verificationSnapshot(
        owner: owner,
        token: token,
        cursor: 7,
        now: DateTime.now(),
        rows: {
          'SONG': [fixtureSong(song, 1)],
        },
      ),
    );
    // Materialize the baseline through the real receive path before editing it.
    ChangeFeedPage page(int after, List<Map<String, Object?>> changes) =>
        ChangeFeedPage.decode(
          jsonEncode({
            'after_seq': after,
            'next_seq': after + changes.length,
            'head_seq': after + changes.length,
            'has_more': false,
            'changes': changes,
          }),
          owner: owner,
          expectedAfter: after,
        );
    await store.applyChangeFeed(page(7, []), snapshotToken: token);
    var repo = LocalRepository(store);
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.song,
        entityId: song,
        baseRevision: 1,
        draft: fixtureSong(song, 1, note: '오프라인 메모'),
        changes: {'note': '오프라인 메모'},
      ),
    );
    final stale = (await repo.pending()).single;
    final recording = <String, Object?>{
      'id': rec,
      'metadata_state': 'DRAFT',
      'song_id': song,
      'title_snapshot': '보존할 새 녹음',
      'artist_snapshot': '합성 가수',
      'version_code': 'NORMAL',
      'key_mode': 'ORIGINAL',
      'key_shift': 0,
      'note': '오프라인 녹음 메모',
      'recorded_at': '2026-10-01T00:00:00Z',
      'timezone_id': 'UTC',
      'timezone_offset_minutes': 0,
    };
    final bytes = <int>[1, 2, 3, 4]; // Deliberately not real/valid audio.
    final file = <String, Object?>{
      'sha256': sha256.convert(bytes).toString(),
      'size_bytes': bytes.length,
      'duration_ms': 1000,
      'codec': 'AAC_LC',
      'sample_rate': 48000,
      'channels': 1,
      'capture_integrity': 'VALIDATED',
    };
    await repo.save(
      repo.prepareCreate(
        entity: LocalEntity.recording,
        entityId: rec,
        draft: recording,
        changes: recording,
      ),
    );
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.recording,
        entityId: rec,
        baseRevision: 0,
        draft: {...recording, 'metadata_state': 'SAVED', 'file': file},
        changes: {'metadata_state': 'SAVED', 'file': file},
      ),
    );
    final paths = await AccountPaths.create(run, owner, AppEnvironment.dev);
    final audio = await paths.checkedFile(paths.audioPath(rec));
    await audio.writeAsBytes(bytes, flush: true);
    await manager.logout();
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    try {
      await db.verifyReady();
      await db.customStatement(
        "INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at) VALUES(?,?,?,?,4,'SAVED',0,0)",
        [rec, owner, 'audio/$rec.m4a', file['sha256']],
      );
    } finally {
      await db.close();
    }
    store = await manager.openAccount(owner);
    await store.applyChangeFeed(
      page(7, [
        {
          'change_seq': 8,
          'entity_type': 'SONG',
          'entity_id': song,
          'revision': 2,
          'operation': 'DELETE',
          'payload': {
            'id': song,
            'status': 'DELETED',
            'revision': 2,
            'deleted_at': '2026-10-01T00:00:00Z',
          },
        },
      ]),
      snapshotToken: token,
    );
    repo = LocalRepository(store);
    final transport = DeletedRecordingTransport(recording, file);
    Future<AuthSession> session() async => AuthSession(
      userId: owner,
      deviceId: fixtureId(2),
      accessToken: 'synthetic-only',
      refreshToken: 'unused',
      accessExpiresAt: DateTime.utc(2099),
      refreshExpiresAt: DateTime.utc(2099),
    );
    await repo.dispatch(transport: transport, session: session);
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    final copy = (await repo.read(LocalEntity.recording, rec))!;
    final value = jsonDecode(copy.serverJson!) as Map;
    final pending = await repo.pendingWork();
    final backend = RepositorySyncBackend(repo, transport, session);
    await backend.load();
    final result = <String, bool>{
      '삭제된 곡 부활 없음': (await repo.read(LocalEntity.song, song))!.tombstone,
      '오래된 곡 수정 전송 없음':
          pending.length == 1 &&
          pending.single.opId == stale.opId &&
          pending.single.payload == stale.payload &&
          pending.single.attemptCount == 0,
      '새 녹음 미연결·저장 완료':
          value['song_id'] == null &&
          value['metadata_state'] == 'SAVED' &&
          value['note'] == recording['note'],
      '파일 바이트 보존':
          sha256.convert(await audio.readAsBytes()).toString() ==
          file['sha256'],
      '재시작 후 재연결 안내 유지':
          backend.statusMessage?.contains('새 녹음 1개를 미연결로 보존') == true,
      '파일 업로드 없이 정보 2회 전송':
          transport.requests.length == 2 &&
          transport.requests.first.method == 'POST' &&
          transport.requests.last.method == 'PATCH',
    };
    await File('${run.path}/result.json')
        .writeAsString(jsonEncode(result), flush: true);
    return result;
  } finally {
    await manager.logout();
  }
}

class DeletedSongVerificationScreen extends StatefulWidget {
  const DeletedSongVerificationScreen({super.key});
  @override
  State<DeletedSongVerificationScreen> createState() =>
      _DeletedSongVerificationState();
}

class _DeletedSongVerificationState
    extends State<DeletedSongVerificationScreen> {
  bool busy = false;
  Map<String, bool>? results;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('삭제된 곡·새 녹음 보존')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('합성 자료와 실제 로컬 저장소를 사용합니다. 서버 통신·실제 녹음·사용자 자료 삭제는 하지 않습니다.'),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                    results = null;
                  });
                  try {
                    final support = await getApplicationSupportDirectory();
                    final value = await verifyDeletedSong(
                      Directory('${support.path}/isolated-deletion-checks'),
                    );
                    if (mounted) setState(() => results = value);
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => error = '검증 실패: ${e.runtimeType}. AI에게 알려 주세요.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '검증 중' : '검증 시작'),
        ),
        if (error != null) Text(error!),
        for (final row in results?.entries ?? <MapEntry<String, bool>>[])
          ListTile(
            title: Text(row.key),
            trailing: Text(row.value ? '통과' : '실패'),
          ),
        if (results != null && results!.values.every((v) => v))
          const Text('6개 항목 통과. 삭제된 곡의 새 녹음은 미연결로 보존됩니다. 원하는 곡에 다시 연결해 주세요.'),
      ],
    ),
  );
}
