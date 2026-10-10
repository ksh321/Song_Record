import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/recorder/recording_relink_screen.dart';

import 'recording_input_test.dart' as input;
import 'support/completed_capture_fixture.dart';

const target = '00000000-0000-4000-8000-000000001806';

class RelinkTransport extends input.Transport {
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    if (request.path == '/v1/songs') {
      fence();
      requests.add(request);
      final b = jsonDecode(request.body) as Map<String, dynamic>;
      final response = MutationResponse(
        201,
        jsonEncode({
          'created': true,
          'canonical_song_id': b['id'],
          'song': {
            'id': b['id'],
            'source_type': 'MANUAL',
            'tj_number': null,
            'title': b['title'],
            'artist': b['artist'],
            'version_code': b['version_code'],
            'representative_key_mode': null,
            'representative_key_shift': null,
            'representative_recording_id': null,
            'tier': null,
            'note': b['note'],
            'lifecycle_state': 'ACTIVE',
            'revision': 1,
            'updated_at': '2026-10-10T02:00:00.000Z',
          },
        }),
      );
      return response;
    }
    final response = await super.send(request, session, fence);
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-relink-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    await capture(repo);
    await repo.saveRecordingInput(
      rec,
      input.fields(),
      repo.recordingSaveOperationIds(),
    );
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<Map<String, dynamic>> row() async {
    final c = (await repo.read(LocalEntity.recording, rec))!;
    return jsonDecode(c.localJson ?? c.serverJson!) as Map<String, dynamic>;
  }

  Future<void> song({String state = 'ACTIVE'}) => repo.save(
    repo.prepareCreate(
      entity: LocalEntity.song,
      entityId: target,
      draft: {
        'source_type': 'MANUAL',
        'title': 'other',
        'artist': 'Other',
        'version_code': 'MR',
        'tier': 'B',
        'lifecycle_state': state,
      },
      changes: {
        'source_type': 'MANUAL',
        'title': 'other',
        'artist': 'Other',
        'version_code': 'MR',
        'manual_reason': 'TJ_NOT_FOUND',
        'note': '',
      },
    ),
  );
  test('explicit relink and unlink preserve snapshots, file and strict wire revision', () async {
    final t = RelinkTransport();
    expect(
      await repo.dispatch(transport: t, session: () async => input.session()),
      4,
    );
    await song();
    final old = await row();
    final copy = (await repo.read(LocalEntity.recording, rec))!;
    final command = repo.prepareRecordingRelink(old, copy.revision, target);
    await command();
    await command();
    final linked = await row();
    for (final field in [
      'title_snapshot',
      'artist_snapshot',
      'key_mode',
      'key_shift',
      'version_code',
      'note',
      'tier',
      'file',
      'recorded_at',
    ]) {
      expect(linked[field], old[field]);
    }
    expect(linked['song_id'], target);
    expect(linked['link_revision'], 2);
    expect(await store.readLocalAudio(rec), bytes);
    expect(
      await repo.dispatch(transport: t, session: () async => input.session()),
      2,
    );
    expect(t.requests.last.path, '/v1/recordings/$rec/song');
    expect(jsonDecode(t.requests.last.body).keys.toSet(), {
      'song_id',
      'base_revision',
    });
    final ack = (await repo.read(LocalEntity.recording, rec))!;
    await repo.prepareRecordingRelink(await row(), ack.revision, null)();
    expect(
      await repo.dispatch(transport: t, session: () async => input.session()),
      1,
    );
    expect((await row())['song_id'], null);
    expect((await row())['link_revision'], 3);
    expect((await repo.savedRecordings()).length, 1);
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    expect((await row())['title_snapshot'], old['title_snapshot']);
    expect(await store.readLocalAudio(rec), bytes);
  });
  test('trashed or missing target cannot alter metadata or queue', () async {
    await song(state: 'TRASHED');
    final old = await row();
    final count = (await repo.pending()).length;
    for (final id in [target, other]) {
      await expectLater(
        repo.prepareRecordingRelink(old, 0, id)(),
        throwsStateError,
      );
      expect(await row(), old);
      expect((await repo.pending()).length, count);
    }
  });
  test('stale editor and changed account cannot relink', () async {
    await song();
    final old = await row();
    await repo.prepareRecordingRelink(old, 0, target)();
    await expectLater(
      repo.prepareRecordingRelink(old, 0, null)(),
      throwsStateError,
    );
    final linked = await row();
    await manager.openAccount(other);
    await expectLater(
      repo.prepareRecordingRelink(linked, 0, null)(),
      throwsStateError,
    );
  });
  testWidgets('search and cancelled confirmation do not create link edits', (
    t,
  ) async {
    await t.runAsync(song);
    final old = (await t.runAsync(row))!;
    final rows = (await t.runAsync(() => repo.watchActiveSongs().first))!;
    final count = (await t.runAsync(repo.pending))!.length;
    await t.pumpWidget(
      MaterialApp(
        home: RecordingRelinkScreen(
          recording: old,
          revision: 0,
          repository: repo,
          isCurrent: (_) => true,
          watchSongs: () => Stream.value(rows),
        ),
      ),
    );
    await t.pump();
    await t.enterText(find.byType(TextField), 'none');
    await t.pump();
    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'OTHER');
    await t.pump();
    await t.tap(find.text('other'));
    await t.pumpAndSettle();
    expect(find.text('연결 저장'), findsOneWidget);
    expect(find.textContaining('녹음 당시 제목'), findsOneWidget);
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    expect(await t.runAsync(row), old);
    expect((await t.runAsync(repo.pending))!.length, count);
  });
  testWidgets(
    'song read failure preserves saved recording and offers no false result',
    (t) async {
      final old = (await t.runAsync(row))!;
      await t.pumpWidget(
        MaterialApp(
          home: RecordingRelinkScreen(
            recording: old,
            revision: 0,
            repository: repo,
            isCurrent: (_) => true,
            watchSongs: () => Stream.error(StateError('fixture')),
          ),
        ),
      );
      await t.pump();
      expect(find.text('내 곡을 확인하지 못했어요. 녹음 정보와 파일은 유지돼요.'), findsOneWidget);
      expect(find.text('검색 결과가 없어요.'), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(await t.runAsync(row), old);
    },
  );
}
