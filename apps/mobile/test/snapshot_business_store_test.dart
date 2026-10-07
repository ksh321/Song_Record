import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/asset_deletion_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/database/snapshot_business_store.dart';
import 'package:song_record/core/database/snapshot_download_store.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';

import 'change_payload_validation_test.dart' show songChange, recordingWire;
import 'snapshot_playlist_item_projection_test.dart'
    show playlistSource, playlistItemSource;
import 'snapshot_projection_integration_test.dart'
    show initialProjectionSurvivesDeltaFailure, initialProjectionPreservesResolutionEvidence;
import 'snapshot_receiver_test.dart' show FakeTransport, session;
import 'support/business_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('initial publication remains readable when delta fails before send',
      initialProjectionSurvivesDeltaFailure);
  test('initial publication preserves canonical and conflict evidence',
      initialProjectionPreservesResolutionEvidence);
  const owner = '11111111-1111-4111-8111-111111111111';
  const token = '22222222-2222-4222-8222-222222222222';
  const song = '33333333-3333-4333-8333-333333333333';
  const other = '44444444-4444-4444-8444-444444444444';
  late DateTime now;
  late AccountDatabase db;
  late SnapshotDownloadStore downloads;
  late SnapshotBusinessStore business;

  setUp(() async {
    now = DateTime.utc(2026, 9, 30);
    db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    downloads = SnapshotDownloadStore(
      db,
      requireActive: () {},
      clock: () => now,
    );
    business = SnapshotBusinessStore(
      db,
      requireActive: () {},
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  Map<String, dynamic> fixtureFor({bool invalidSecondSong = false}) {
    final fixture = businessSnapshotFixture();
    if (invalidSecondSong) {
      final page = (fixture['pages'] as List).singleWhere(
        (dynamic value) => value['entity'] == 'SONG',
      ) as Map<String, dynamic>;
      final payload = <String, dynamic>{
        ...songChange(other, 1, title: ''),
        'user_id': owner,
      };
      (page['entries'] as List).add({
        'ordinal': 2,
        'resource_id': other,
        'payload': payload,
        'canonical_payload': canonicalJson(payload),
      });
      (fixture['manifest']['entity_counts'] as Map)['SONG'] = 2;
      refreshSnapshotHash(fixture);
    }
    return fixture;
  }

  Future<void> baseline({
    bool invalidSecondSong = false,
    bool apply = true,
  }) async {
    final fixture = fixtureFor(invalidSecondSong: invalidSecondSong);
    await downloads.begin(token, jsonEncode(fixture['manifest']));
    for (final page in fixture['pages'] as List) {
      await downloads.append(token, page['entity'] as String, 0, jsonEncode(page));
    }
    await downloads.verify(token);
    if (apply) await downloads.apply(token);
  }

  Future<Map<String, int>> project([String expectedToken = token]) =>
      business.apply(expectedToken, AssetDeletionStore(db, () {}, () => now));

  Future<List<Map<String, Object?>>> rows(String table) async =>
      (await db.customSelect('SELECT * FROM $table').get())
          .map((row) => row.data)
          .toList();

  test('shared projection preserves drafts, raw rows and cursor on replay', () async {
    await baseline();
    final original = await rows('snapshot_download_rows');
    final cursor = await rows('sync_cursors');
    final draft = canonicalJson(songChange(song, 0, title: 'local draft'));
    await db.customStatement(
      '''INSERT INTO metadata_copies(
        user_id,entity_type,entity_id,local_payload,updated_at
      ) VALUES(?,'SONG',?,?,0)''',
      [owner, song, draft],
    );

    expect(await project(), isEmpty);
    final copy = (await rows('metadata_copies')).single;
    expect(copy['server_revision'], 1);
    expect(jsonDecode(copy['server_payload'] as String)['note'], '한글 🎵');
    expect(copy['local_payload'], draft);
    expect(await rows('local_mutations'), isEmpty);
    expect(await rows('snapshot_download_rows'), original);
    expect(await rows('sync_cursors'), cursor);

    await project();
    expect(await rows('metadata_copies'), [copy]);
    expect(await rows('sync_cursors'), cursor);
  });

  test('a later invalid business row rolls back the first projected song', () async {
    await baseline(invalidSecondSong: true);
    final original = await rows('snapshot_download_rows');
    final cursor = await rows('sync_cursors');
    await expectLater(project(), throwsFormatException);
    expect(await rows('metadata_copies'), isEmpty);
    expect(await rows('snapshot_download_rows'), original);
    expect(await rows('sync_cursors'), cursor);
  });

  test('outer transaction failure rolls back projection and cursor together', () async {
    await baseline();
    final cursor = await rows('sync_cursors');
    await expectLater(
      db.transaction(() async {
        await project();
        expect(await rows('metadata_copies'), hasLength(1));
        await db.customStatement(
          'UPDATE sync_cursors SET last_change_seq=8 WHERE singleton=1',
        );
        throw StateError('Injected caller failure');
      }),
      throwsStateError,
    );
    expect(await rows('metadata_copies'), isEmpty);
    expect(await rows('sync_cursors'), cursor);
  });

  test('a stale snapshot token cannot materialize the current baseline', () async {
    await baseline();
    await expectLater(project(other), throwsStateError);
    expect(await rows('metadata_copies'), isEmpty);
    expect(await project(), isEmpty);
    expect(await rows('metadata_copies'), hasLength(1));
  });

  test('publication failure preserves staging, cursor and resume together', () async {
    await baseline(invalidSecondSong: true, apply: false);
    await db.customStatement(
      'UPDATE sync_cursors SET snapshot_resume=? WHERE singleton=1',
      [jsonEncode({'phase': 'RECEIVING', 'token': token})],
    );
    final cursor = await rows('sync_cursors');
    final staged = await rows('snapshot_download_rows');
    await expectLater(
      downloads.apply(token, projectBusiness: () async { await project(); }),
      throwsFormatException,
    );
    expect(await rows('metadata_copies'), isEmpty);
    expect(await rows('snapshot_baseline'), isEmpty);
    expect(await rows('sync_cursors'), cursor);
    expect(await rows('snapshot_download_rows'), staged);
    expect((await downloads.read(token)).state, 'VERIFIED');
  });

  for (final loseLease in [false, true]) {
    test('replacement publication rolls back and reopens: lease=$loseLease', () async {
      final directory = await Directory.systemTemp.createTemp('sr-business-rollback-');
      final paths = await AccountPaths.create(directory, owner, AppEnvironment.dev);
      final databaseFile = await paths.databaseFile();
      AccountDatabase openDatabase() => AccountDatabase(
        NativeDatabase(databaseFile), userId: owner, environment: AppEnvironment.dev,
      );
      var storage = openDatabase();
      var active = true;
      void fence() {
        if (!active) throw StateError('Injected lost account lease');
      }
      SnapshotDownloadStore downloader() => SnapshotDownloadStore(
        storage, requireActive: fence, clock: () => now,
      );
      Future<void> publish(String value) async {
        await downloader().apply(value, projectBusiness: () async {
          await SnapshotBusinessStore(storage, requireActive: fence, clock: () => now)
              .apply(value, AssetDeletionStore(storage, fence, () => now));
          if (loseLease && value == other) {
            final projected = await storage.customSelect(
              "SELECT server_revision FROM metadata_copies WHERE entity_type='SONG'",
            ).getSingle();
            expect(projected.read<int>('server_revision'), 2);
            active = false;
          }
        });
      }
      Future<void> stage(Map<String, dynamic> fixture, String value) async {
        await downloader().begin(value, jsonEncode(fixture['manifest']));
        for (final page in fixture['pages'] as List) {
          await downloader().append(value, page['entity'] as String, 0, jsonEncode(page));
        }
        await downloader().verify(value);
      }
      Future<Map<String, Object?>> retained() async {
        final result = <String, Object?>{};
        for (final table in [
          'metadata_copies', 'sync_cursors', 'snapshot_baseline',
          'snapshot_downloads', 'snapshot_download_rows', 'snapshot_download_progress',
          'local_mutations', 'local_recording_files', 'recording_journals',
        ]) {
          result[table] = (await storage.customSelect('SELECT * FROM $table').get())
              .map((row) => row.data).toList();
        }
        return result;
      }
      try {
        await storage.verifyReady();
        await stage(businessSnapshotFixture(), token);
        await publish(token);
        final replacement = businessSnapshotFixture();
        replacement['manifest']['snapshot_token'] = other;
        replacement['manifest']['snapshot_cursor'] = 8;
        for (final page in replacement['pages'] as List) {
          page['snapshot_token'] = other;
          page['snapshot_cursor'] = 8;
        }
        final syncPage = (replacement['pages'] as List).singleWhere(
          (dynamic page) => page['entity'] == 'USER_SYNC_STATE',
        );
        final syncRow = (syncPage['entries'] as List).single;
        syncRow['payload']['last_change_seq'] = 8;
        syncRow['canonical_payload'] = canonicalJson(syncRow['payload'] as Map<String, dynamic>);
        replaceBusinessSnapshotRows(replacement, 'SONG', [
          {...songChange(song, 2, title: 'replacement title'), 'user_id': owner},
        ]);
        replaceBusinessSnapshotRows(replacement, 'TAG', [{
          'id': other, 'user_id': owner, 'revision': 1, 'name': 'replacement tag',
          'updated_at': '2026-09-30T00:00:00Z', 'archived_at': null,
        }]);
        await stage(replacement, other);
        await storage.customStatement(
          'UPDATE sync_cursors SET baseline_complete=0,snapshot_resume=? WHERE singleton=1',
          [jsonEncode({
            'version': 1, 'op_id': song, 'phase': 'RECEIVING', 'token': other,
            'expires_at': replacement['manifest']['expires_at'],
          })],
        );
        if (!loseLease) {
          // Fail only after the first business write and publication writes.
          await storage.customStatement('''
            CREATE TEMP TRIGGER fail_replacement_tag BEFORE INSERT ON metadata_copies
            WHEN NEW.entity_type='TAG'
              AND EXISTS(SELECT 1 FROM metadata_copies WHERE entity_type='SONG' AND server_revision=2)
              AND EXISTS(SELECT 1 FROM sync_cursors WHERE last_change_seq=8 AND snapshot_resume IS NULL)
            BEGIN SELECT RAISE(ABORT, 'Injected replacement SQL failure'); END
          ''');
        }
        final before = await retained();
        await expectLater(publish(other), throwsA(predicate<Object>((error) =>
            error.toString().contains(loseLease
                ? 'Injected lost account lease' : 'Injected replacement SQL failure'))));
        expect(await retained(), before);
        await storage.close();
        storage = openDatabase();
        await storage.verifyReady();
        expect(await retained(), before);
        // A fresh lease/connection can apply the retained verified download.
        active = true;
        await downloader().apply(other, projectBusiness: () async {
          await SnapshotBusinessStore(storage, requireActive: fence, clock: () => now)
              .apply(other, AssetDeletionStore(storage, fence, () => now));
        });
        final cursor = await storage.customSelect('SELECT * FROM sync_cursors').getSingle();
        expect(cursor.read<int>('last_change_seq'), 8);
        expect(cursor.read<int>('baseline_complete'), 1);
        expect(cursor.readNullable<String>('snapshot_resume'), isNull);
        expect((await storage.customSelect('SELECT snapshot_token FROM snapshot_baseline')
            .getSingle()).read<String>('snapshot_token'), other);
      } finally {
        await storage.close();
        expect(directory.path.split(Platform.pathSeparator).last,
            startsWith('sr-business-rollback-'));
        await directory.delete(recursive: true);
      }
    });
  }

  test('expiry after projection rolls back publication and business copies', () async {
    await baseline(apply: false);
    final cursor = await rows('sync_cursors');
    await expectLater(
      downloads.apply(token, projectBusiness: () async {
        await project();
        expect(await rows('metadata_copies'), hasLength(1));
        now = now.add(const Duration(minutes: 30));
      }),
      throwsStateError,
    );
    expect(await rows('metadata_copies'), isEmpty);
    expect(await rows('snapshot_baseline'), isEmpty);
    expect(await rows('sync_cursors'), cursor);
    expect((await rows('snapshot_downloads')).single['state'], 'VERIFIED');
  });

  test('an older applied baseline can be projected after TTL without cursor rewind', () async {
    await baseline();
    await db.customStatement(
      'UPDATE sync_cursors SET last_change_seq=8 WHERE singleton=1',
    );
    final cursor = await rows('sync_cursors');
    now = now.add(const Duration(hours: 1));
    await downloads.apply(token, projectBusiness: () async { await project(); });
    expect(await rows('metadata_copies'), hasLength(1));
    expect(await rows('sync_cursors'), cursor);
  });

  for (final tombstone in [false, true]) {
    test('initial apply preserves newer copy and frozen retry: tombstone=$tombstone', () async {
      final directory = await Directory.systemTemp.createTemp('sr-business-retry-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
        clock: () => now,
      );
      try {
        var store = await manager.openAccount(owner);
        final draft = songChange(song, 0, title: 'private draft');
        await store.saveEdit(LocalEdit(
          opId: other, entity: LocalEntity.song, entityId: song,
          operation: LocalOperation.create, baseRevision: 0,
          draft: draft,
          changes: {
            'id': song, 'source_type': 'MANUAL', 'title': 'private draft',
            'artist': 'private artist', 'manual_reason': 'NOT_FOUND',
          },
        ));
        final first = (await store.claimMutation())!;
        expect(await store.deferMutation(first, 'RETRY', 'HTTP_503', status: 503), isTrue);
        now = (await store.retryStatus(other))!.nextAttemptAt!;
        final second = (await store.claimMutation())!;
        expect(second.attempt, 2);
        expect(second.body, first.body);
        expect(second.hash, first.hash);
        expect(await store.deferMutation(second, 'RETRY', 'HTTP_503', status: 503), isTrue);
        expect((await store.retryStatus(other))!.automaticRetriesClaimed, 1);
        final paths = await AccountPaths.create(directory, owner, AppEnvironment.dev);
        final raw = AccountDatabase(
          NativeDatabase(await paths.databaseFile()),
          userId: owner, environment: AppEnvironment.dev,
        );
        try {
          await raw.verifyReady();
          await raw.customStatement(
            '''UPDATE metadata_copies SET server_revision=3,server_payload=?,tombstone=?
               WHERE entity_type='SONG' AND entity_id=?''',
            [canonicalJson(songChange(song, 3, title: 'newer server copy')),
              tombstone ? 1 : 0, song],
          );
        } finally {
          await raw.close();
        }
        // This local tag is absent from the initial snapshot and must survive.
        await store.saveEdit(LocalEdit(
          opId: '66666666-6666-4666-8666-666666666666',
          entity: LocalEntity.tag, entityId: owner,
          operation: LocalOperation.create, baseRevision: 0,
          draft: {'name': 'offline only'}, changes: {'name': 'offline only'},
        ));
        Future<Map<dynamic, dynamic>> tables() async =>
            (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
        final before = await tables();
        expect(before['mutation_wire_requests'], hasLength(1));
        final fixture = businessSnapshotFixture();
        await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
        for (final page in fixture['pages'] as List) {
          await store.appendSnapshotPage(token, page['entity'] as String, 0, jsonEncode(page));
        }
        await store.verifySnapshotDownload(token);
        await store.applySnapshotDownload(token);
        Future<void> preserved() async {
          final after = await tables();
          for (final name in before.keys) {
            if (name == 'sync_cursors' || (name as String).startsWith('snapshot_')) {
              continue;
            }
            expect(after[name], before[name], reason: 'Preserve $name');
          }
          final copy = (await store.readMetadata(LocalEntity.song, song))!;
          expect(copy.revision, 3);
          expect(copy.tombstone, tombstone);
          expect(copy.localJson, canonicalJson(draft));
          expect(jsonDecode(copy.serverJson!)['title'], 'newer server copy');
          final retry = (await store.retryStatus(other))!;
          expect(retry.attemptCount, 2);
          expect(retry.automaticRetriesClaimed, 1);
          expect(retry.queueState, 'RETRY');
        }
        await preserved();
        await manager.logout();
        store = await manager.openAccount(owner);
        await preserved();
        await store.applySnapshotDownload(token);
        await preserved();
      } finally {
        await manager.logout();
        expect(directory.path.split(Platform.pathSeparator).last,
            startsWith('sr-business-retry-'));
        await directory.delete(recursive: true);
      }
    });
  }

  test('paged relations survive restart and expose only the captured snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('sr-business-pages-');
    AccountStoreManager managerFor() => AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
      clock: () => now,
    );
    var manager = managerFor();
    String itemId(int index) =>
        '77777777-7777-4777-8777-${(index + 1).toString().padLeft(12, '0')}';
    try {
      var store = await manager.openAccount(owner);
      final fixture = businessSnapshotFixture();
      final pages = fixture['pages'] as List;
      final parent = playlistSource();
      void replaceRows(String entity, List<Map<String, dynamic>> values) {
        final page = pages.singleWhere((dynamic p) => p['entity'] == entity) as Map;
        page['entries'] = [
          for (var index = 0; index < values.length; index++)
            {
              'ordinal': index + 1,
              'resource_id': values[index]['id'],
              'payload': values[index],
              'canonical_payload': canonicalJson(values[index]),
            },
        ];
        (fixture['manifest']['entity_counts'] as Map)[entity] = values.length;
      }
      replaceRows('PLAYLIST', [parent]);
      replaceRows('PLAYLIST_ITEM', [
        for (var index = 0; index < 101; index++)
          {
            ...playlistItemSource(),
            'id': itemId(index),
            'position': index,
            'song_id': index == 0 ? song : null,
            'candidate_brand': index == 0 ? null : 'TJ',
            'candidate_number': index == 0 ? null : '${1000 + index}',
            'candidate_snapshot': index == 0
                ? null
                : {'title': 'captured $index', 'artist': 'synthetic'},
            'entry_key': index == 0 ? 'manual:$song' : 'tj:${1000 + index}',
          },
      ]);
      refreshSnapshotHash(fixture);
      var liveSong = songChange(song, 1);
      var creates = 0;
      final transport = FakeTransport();
      transport.respond = (request) async {
        if (request.method == 'POST') {
          return SnapshotHttpResponse(202, jsonEncode({
            'operation_id': other,
            'snapshot_token': token,
            'status': 'BUILDING',
            'status_url': '/v1/sync/snapshots/$token',
          }));
        }
        final entity = request.query['entity'];
        if (entity == null) {
          return SnapshotHttpResponse(200, jsonEncode(fixture['manifest']));
        }
        final page = pages.singleWhere((dynamic p) => p['entity'] == entity) as Map;
        final entries = page['entries'] as List;
        final cursor = request.query['cursor'];
        final after = cursor == null ? 0 : int.parse(cursor.substring('sp1.p'.length));
        final batch = entries.skip(after).take(50).toList();
        final end = after + batch.length;
        return SnapshotHttpResponse(200, jsonEncode({
          ...page,
          'entries': batch,
          'next_cursor': end < entries.length ? 'sp1.p$end' : null,
        }));
      };
      SnapshotReceiver receiver() => SnapshotReceiver(
        store: store,
        transport: transport,
        newOperationId: () { creates++; return other; },
        clock: () => now,
      );
      var runner = receiver();
      var reopened = false;
      var result = SnapshotStep.progressed;
      for (var step = 0; step < 40; step++) {
        result = await runner.step(session);
        if (result == SnapshotStep.complete) break;
        expect(result, SnapshotStep.progressed);
        expect(await store.readMetadata(LocalEntity.playlist, other), isNull);
        expect(await store.readMetadata(LocalEntity.playlistItem, itemId(0)), isNull);
        expect(await store.readCursor(), isNull);
        final request = transport.requests.last;
        if (!reopened && request.query['entity'] == 'PLAYLIST_ITEM') {
          expect((await store.snapshotDownloadState(token))
              .progress['PLAYLIST_ITEM']?.ordinal, 50);
          // The server changes after capture; its immutable token pages above
          // still contain the old values, even after a new account manager.
          liveSong = songChange(song, 2, title: 'after capture');
          await manager.logout();
          manager = managerFor();
          store = await manager.openAccount(owner);
          runner = receiver();
          reopened = true;
        }
      }
      expect(result, SnapshotStep.complete);
      expect(reopened, isTrue);
      expect(creates, 1);
      expect(await store.readCursor(), 7);
      expect(jsonDecode((await store.readMetadata(LocalEntity.song, song))!
          .serverJson!)['title'], 'server');
      for (final index in [0, 49, 50, 99, 100]) {
        final value = jsonDecode((await store.readMetadata(
          LocalEntity.playlistItem, itemId(index),
        ))!.serverJson!) as Map;
        expect(value['position'], index);
        expect(value['playlist_id'], parent['id']);
        expect(value['playlist_revision'], 8);
        expect(value['entry_key'], index == 0 ? 'manual:$song' : 'tj:${1000 + index}');
      }
      expect(transport.requests.where((r) =>
          r.query['entity'] == 'PLAYLIST_ITEM').map((r) => r.query['cursor']),
          [null, 'sp1.p50', 'sp1.p100']);
      final captured = (await store.snapshotBaselineRecord('SONG', song))!
          .entry!.canonicalPayload;
      await store.applyChangeFeed(ChangeFeedPage.decode(jsonEncode({
        'after_seq': 7, 'next_seq': 8, 'head_seq': 8, 'has_more': false,
        'changes': [{
          'change_seq': 8, 'entity_type': 'SONG', 'entity_id': song,
          'revision': 2, 'operation': 'UPSERT', 'payload': liveSong,
        }],
      }), owner: owner, expectedAfter: 7), snapshotToken: token);
      expect(await store.readCursor(), 8);
      expect(jsonDecode((await store.readMetadata(LocalEntity.song, song))!
          .serverJson!)['title'], 'after capture');
      expect((await store.snapshotBaselineRecord('SONG', song))!
          .entry!.canonicalPayload, captured);
      expect(await store.pendingMutations(), isEmpty);
    } finally {
      await manager.logout();
      expect(directory.path.split(Platform.pathSeparator).last,
          startsWith('sr-business-pages-'));
      await directory.delete(recursive: true);
    }
  });

  for (final duplicateTag in [false, true]) {
    test('recording projection preserves registered audio and journal: duplicate=$duplicateTag', () async {
      const rec = '55555555-5555-4555-8555-555555555555';
      const tag = '66666666-6666-4666-8666-666666666666';
      final directory = await Directory.systemTemp.createTemp('sr-business-audio-');
      AccountStoreManager managerFor() => AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
        clock: () => now,
      );
      var manager = managerFor();
      try {
        var store = await manager.openAccount(owner);
        final paths = await AccountPaths.create(directory, owner, AppEnvironment.dev);
        final bytes = List<int>.generate(32, (index) => index);
        final checksum = sha256.convert(bytes).toString();
        await (await paths.checkedFile(paths.audioPath(rec))).writeAsBytes(bytes);
        final draft = <String, dynamic>{
          ...recordingWire('RecordingDraft'),
          'id': rec, 'song_id': song,
          'title_snapshot': '당시 곡명', 'artist_snapshot': '당시 가수',
          'version_code': 'LIVE', 'key_mode': 'MALE', 'key_shift': 2,
          'note': '미전송 메모',
        };
        await store.saveEdit(LocalEdit(
          opId: other, entity: LocalEntity.recording, entityId: rec,
          operation: LocalOperation.create, baseRevision: 0,
          draft: draft, changes: draft,
        ));
        await store.recordFileAndJournal(
          recordingId: rec, operationId: tag,
          state: FilePresence.inputPending, phase: JournalPhase.committed,
          pending: false, checksum: checksum, sizeBytes: bytes.length,
          recovery: draft,
        );
        final journal = await store.readJournal(rec);
        Future<Map<dynamic, dynamic>> tables() async =>
            (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
        final before = await tables();
        final fixture = businessSnapshotFixture();
        final file = <String, dynamic>{
          ...Map<String, dynamic>.from(recordingWire('RecordingSaved')['file'] as Map),
          'sha256': checksum, 'size_bytes': bytes.length,
        };
        replaceBusinessSnapshotRows(fixture, 'RECORDING', [{
          ...draft, 'user_id': owner, 'revision': 1, 'note': '서버 메모',
          'condition_code': 'GOOD', 'condition_name_snapshot': '좋음',
        }]);
        replaceBusinessSnapshotRows(fixture, 'RECORDING_FILE_SPEC', [{
          ...file, 'recording_id': rec, 'user_id': owner,
        }]);
        replaceBusinessSnapshotRows(fixture, 'TAG', [
          for (final id in [tag, other]) {
            'id': id, 'user_id': owner, 'revision': 1,
            'updated_at': '2026-09-30T00:00:00Z',
            'name': '현재 태그 이름', 'archived_at': '2026-09-30T00:00:00Z',
          },
        ]);
        replaceBusinessSnapshotRows(fixture, 'RECORDING_TAG', [
          {'recording_id': rec, 'user_id': owner,
            'tag_id': tag, 'name_snapshot': '당시 태그 하나'},
          {'recording_id': rec, 'user_id': owner,
            'tag_id': duplicateTag ? tag : other, 'name_snapshot': '당시 태그 둘'},
        ]);
        await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
        for (final page in fixture['pages'] as List) {
          await store.appendSnapshotPage(token, page['entity'] as String, 0, jsonEncode(page));
        }
        await store.verifySnapshotDownload(token);
        if (duplicateTag) {
          await expectLater(store.applySnapshotDownload(token), throwsStateError);
          expect(await store.hasCompleteBaseline(), isFalse);
          expect(await store.readCursor(), isNull);
          expect((await tables())['metadata_copies'], before['metadata_copies']);
        } else {
          await store.applySnapshotDownload(token);
          final copy = await store.readMetadata(LocalEntity.recording, rec);
          final server = jsonDecode(copy!.serverJson!) as Map;
          expect(copy.localJson, canonicalJson(draft));
          expect(server['id'], rec);
          expect(server['title_snapshot'], draft['title_snapshot']);
          expect(server['artist_snapshot'], draft['artist_snapshot']);
          expect(server['key_shift'], 2);
          expect(server['version_code'], 'LIVE');
          expect(server['note'], '서버 메모');
          expect(server['condition_code'], 'GOOD');
          expect(server['file'], file);
          expect(server['tag_ids'], [tag, other]);
          expect((server['tags'] as List).map((dynamic t) => t['name_snapshot']),
              ['당시 태그 하나', '당시 태그 둘']);
          expect(await store.readCursor(), 7);
        }
        Future<void> preserved() async {
          final after = await tables();
          for (final name in before.keys) {
            if (name == 'metadata_copies' || name == 'sync_cursors' ||
                (name as String).startsWith('snapshot_')) {
              continue;
            }
            expect(after[name], before[name], reason: '$name must remain unchanged');
          }
          expect(await store.readJournal(rec), journal);
          expect(await store.readLocalAudio(rec), bytes);
          expect((await store.readMetadata(LocalEntity.recording, rec))!.localJson,
              canonicalJson(draft));
        }
        await preserved();
        await manager.logout();
        manager = managerFor();
        store = await manager.openAccount(owner);
        await preserved();
        final otherAccount = await manager.openAccount(other);
        expect(await otherAccount.readMetadata(LocalEntity.recording, rec), isNull);
        expect(await otherAccount.readJournal(rec), isNull);
        await expectLater(otherAccount.readLocalAudio(rec), throwsStateError);
        store = await manager.openAccount(owner);
        await preserved();
      } finally {
        await manager.logout();
        expect(directory.path.split(Platform.pathSeparator).last,
            startsWith('sr-business-audio-'));
        await directory.delete(recursive: true);
      }
    });
  }

  for (final invalid in [false, true]) {
    test('receiver repairs a legacy baseline before completion: invalid=$invalid', () async {
      final directory = await Directory.systemTemp.createTemp('sr-business-legacy-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
        clock: () => now,
      );
      try {
        final paths = await AccountPaths.create(directory, owner, AppEnvironment.dev);
        final legacy = AccountDatabase(
          NativeDatabase(await paths.databaseFile()),
          userId: owner,
          environment: AppEnvironment.dev,
        );
        try {
          await legacy.verifyReady();
          final rawDownloads = SnapshotDownloadStore(
            legacy, requireActive: () {}, clock: () => now,
          );
          final fixture = fixtureFor(invalidSecondSong: invalid);
          await rawDownloads.begin(token, jsonEncode(fixture['manifest']));
          for (final page in fixture['pages'] as List) {
            await rawDownloads.append(
              token, page['entity'] as String, 0, jsonEncode(page),
            );
          }
          await rawDownloads.verify(token);
          await rawDownloads.apply(token);
          await legacy.customStatement(
            'UPDATE sync_cursors SET last_change_seq=8 WHERE singleton=1',
          );
        } finally {
          await legacy.close();
        }
        now = now.add(const Duration(hours: 1));
        var store = await manager.openAccount(owner);
        expect(await store.hasCompleteBaseline(), isTrue);
        expect(await store.readMetadata(LocalEntity.song, song), isNull);
        final transport = FakeTransport()
          ..respond = (_) async => throw StateError('Unexpected HTTP request');
        SnapshotReceiver receiver() => SnapshotReceiver(
          store: store,
          transport: transport,
          newOperationId: () => throw StateError('Unexpected new operation'),
          clock: () => now,
        );
        if (invalid) {
          await expectLater(receiver().step(session), throwsFormatException);
          expect(await store.readMetadata(LocalEntity.song, song), isNull);
        } else {
          expect(await receiver().step(session), SnapshotStep.complete);
          expect((await store.readMetadata(LocalEntity.song, song))?.revision, 1);
          final before = jsonDecode(await store.recoveryData()) as Map;
          await manager.logout();
          store = await manager.openAccount(owner);
          expect(await receiver().step(session), SnapshotStep.complete);
          final after = jsonDecode(await store.recoveryData()) as Map;
          expect(after['tables'], before['tables']);
        }
        expect(await store.readCursor(), 8);
        expect(await store.readSnapshotResume(), isNull);
        expect(await store.pendingMutations(), isEmpty);
        expect(transport.requests, isEmpty);
      } finally {
        await manager.logout();
        expect(
          directory.path.split(Platform.pathSeparator).last,
          startsWith('sr-business-legacy-'),
        );
        await directory.delete(recursive: true);
      }
    });

    test('account publication projects business data atomically: invalid=$invalid', () async {
      final directory = await Directory.systemTemp.createTemp('sr-business-apply-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => directory,
        temporaryDirectory: () async => directory,
        clock: () => now,
      );
      try {
        final store = await manager.openAccount(owner);
        final fixture = fixtureFor(invalidSecondSong: invalid);
        await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
        for (final page in fixture['pages'] as List) {
          await store.appendSnapshotPage(
            token, page['entity'] as String, 0, jsonEncode(page),
          );
        }
        await store.verifySnapshotDownload(token);
        if (invalid) {
          await expectLater(store.applySnapshotDownload(token), throwsFormatException);
          expect(await store.readMetadata(LocalEntity.song, song), isNull);
          expect(await store.readCursor(), isNull);
          expect(await store.hasCompleteBaseline(), isFalse);
          expect((await store.snapshotDownloadState(token)).state, 'VERIFIED');
        } else {
          await store.applySnapshotDownload(token);
          final copy = await store.readMetadata(LocalEntity.song, song);
          expect(copy?.revision, 1);
          expect(jsonDecode(copy!.serverJson!)['note'], '한글 🎵');
          expect(await store.readCursor(), 7);
          expect(await store.hasCompleteBaseline(), isTrue);
          expect(await store.pendingMutations(), isEmpty);
        }
      } finally {
        await manager.logout();
        expect(
          directory.path.split(Platform.pathSeparator).last,
          startsWith('sr-business-apply-'),
        );
        await directory.delete(recursive: true);
      }
    });
  }
}
