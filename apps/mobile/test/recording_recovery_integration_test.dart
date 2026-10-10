import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/recorder/recording_input_screen.dart';

import 'recording_edit_test.dart' show EditTransport;
import 'recording_input_test.dart' as input;
import 'support/completed_capture_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-p18-recovery-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    await capture(repo);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  test('offline partial input reopens with same original; metadata and tier synchronize without uploading audio', () async {
    await repo.preserveRecordingInput(rec, {
      ...input.fields(),
      'title_snapshot': '',
      'key_mode': 'MALE',
      'key_shift': 3,
      'version_code': 'MR',
      'key_edited': true,
      'version_edited': true,
    });
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    final pending = (await repo.pendingRecordings()).single;
    final form = pending['input_form'] as Map;
    expect(form['title_snapshot'], '');
    expect(form['key_shift'], 3);
    expect(form['version_edited'], true);
    expect(await store.readLocalAudio(rec), bytes);
    await expectLater(
      repo.saveRecordingInput(rec, {
        ...input.fields(),
        'title_snapshot': '',
      }, repo.recordingSaveOperationIds()),
      throwsArgumentError,
    );
    expect((await repo.pendingRecordings()).single['id'], rec);
    await repo.saveRecordingInput(
      rec,
      input.fields(),
      repo.recordingSaveOperationIds(),
    );
    final old = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.localJson!,
    ) as Map<String, dynamic>;
    await repo.saveRecordingDetails(
      rec,
      {
        ...input.fields()..remove('song_id'),
        'tier': 'A',
        'version_code': 'MR',
        'recorded_at': '2026-10-09T23:00:00.000Z',
      },
      repo.recordingEditOperationIds(),
      old,
      0,
    );
    final transport = EditTransport();
    expect(
      await repo.dispatch(
        transport: transport,
        session: () async => input.session(),
      ),
      6,
    );
    final remote = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.serverJson!,
    ) as Map<String, dynamic>;
    expect(remote['tier'], 'A');
    expect(remote['version_code'], 'MR');
    expect(remote['recorded_at'], '2026-10-09T23:00:00.000Z');
    expect(transport.requests.last.path, '/v1/recordings/$rec/tier');
    expect(await repo.pendingWork(), isEmpty);
    expect(await store.readLocalAudio(rec), bytes);
    // Independent device directory: received metadata does not imply a local audio copy.
    final second = await Directory.systemTemp.createTemp('sr-p18-second-');
    final secondManager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => second,
      temporaryDirectory: () async => second,
    );
    try {
      final paths = await AccountPaths.create(
        second,
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
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,1,?,0,1)',
        [owner, 'RECORDING', rec, jsonEncode(remote)],
      );
      await db.customStatement(
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,1,?,0,1)',
        [
          owner,
          'RECORDING_ASSET',
          rec,
          jsonEncode({
            'recording_id': rec,
            'user_id': owner,
            'cloud_state': 'NONE',
          }),
        ],
      );
      await db.close();
      final otherStore = await secondManager.openAccount(owner);
      final catalog = await LocalRepository(otherStore).recordingCatalog();
      expect(catalog.rows.single['tier'], 'A');
      expect(catalog.rows.single['version_code'], 'MR');
      final status = catalog.rows.single['_file_status'] as RecordingFileStatus;
      expect(status.device, DeviceAudioState.missing);
      expect(status.canPlay, isFalse);
      expect(status.filesConfirmedAbsent, isTrue);
      await expectLater(otherStore.readLocalAudio(rec), throwsStateError);
      expect(await store.readLocalAudio(rec), bytes);
    } finally {
      await secondManager.logout();
      await second.delete(recursive: true);
    }
  });

  test('multiple tags keep historical names after rename/archive and condition can be cleared without changing audio', () async {
    const secondTag = '00000000-0000-4000-8000-000000001821';
    for (final tag in [other, secondTag]) {
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.tag,
          entityId: tag,
          draft: {
            'name': tag == other ? 'first' : 'second',
            'archived_at': null,
          },
          changes: {'name': tag == other ? 'first' : 'second'},
        ),
      );
    }
    await repo.saveRecordingInput(rec, {
      ...input.fields(),
      'tag_ids': [other, secondTag],
    }, repo.recordingSaveOperationIds());
    final tag = (await repo.read(LocalEntity.tag, other))!;
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.tag,
        entityId: other,
        baseRevision: tag.revision,
        draft: {'name': 'renamed', 'archived_at': '2026-10-10T10:00:00Z'},
        changes: {'name': 'renamed'},
      ),
    );
    final old = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.localJson!,
    ) as Map<String, dynamic>;
    await repo.saveRecordingDetails(
      rec,
      {
        ...input.fields()..remove('song_id'),
        'tier': null,
        'condition_code': null,
        'tag_ids': [other, secondTag],
        'note': 'new note',
      },
      repo.recordingEditOperationIds(),
      old,
      0,
    );
    final current = jsonDecode(
      (await repo.read(LocalEntity.recording, rec))!.localJson!,
    ) as Map<String, dynamic>;
    expect(current['tags'], [
      {'id': other, 'name_snapshot': 'first'},
      {'id': secondTag, 'name_snapshot': 'second'},
    ]);
    expect(current['condition_code'], isNull);
    expect(current['condition_name_snapshot'], isNull);
    expect((await repo.selectableRecordingTags()).map((r) => r['id']), [
      secondTag,
    ]);
    expect(await store.readLocalAudio(rec), bytes);
    await manager.logout();
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
    expect(
      jsonDecode(
        (await repo.read(LocalEntity.recording, rec))!.localJson!,
      )['tags'],
      current['tags'],
    );
    expect(await store.readLocalAudio(rec), bytes);
  });

  testWidgets(
    'repeated system back while keyboard is open preserves input across process replacement without saving',
    (t) async {
      final row = (await t.runAsync(repo.pendingRecordings))!.single;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordingInputScreen(
                      recording: row,
                      repository: repo,
                      isCurrent: (_) => true,
                      tagLoader: () async => [],
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('recording-title')),
        'unfinished offline',
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.runAsync(() async {
        await t.binding.handlePopRoute();
        await t.binding.handlePopRoute();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      for (var i = 0; i < 10 && find.text('open').evaluate().isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.textContaining('보존에 실패'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        await manager.logout();
        store = await manager.openAccount(owner);
        repo = LocalRepository(store);
        final pending = (await repo.pendingRecordings()).single;
        expect(
          (pending['input_form'] as Map)['title_snapshot'],
          'unfinished offline',
        );
        expect(pending['metadata_state'], 'DRAFT');
        expect(await store.readLocalAudio(rec), bytes);
      });
    },
  );
}
