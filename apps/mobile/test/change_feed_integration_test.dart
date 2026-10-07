import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';

import 'canonical_song_store_test.dart' as canonical;
import 'change_payload_validation_test.dart' show recordingWire;
import 'metadata_dispatcher_test.dart' show tag;
import 'snapshot_receiver_test.dart' show owner, token, session;
import 'snapshot_sync_backend_test.dart' show Sender;
import 'support/business_snapshot_fixture.dart';

const _song = '33333333-3333-4333-8333-333333333333';
const _playlist = '44444444-4444-4444-8444-444444444444';
const _item = '99999999-9999-4999-8999-999999999999';
const _recording = '66666666-6666-4666-8666-666666666666';

Map<String, dynamic> _wire() => jsonDecode(
    File('../../fixtures/contracts/change-feed-wire.json').readAsStringSync())
    as Map<String, dynamic>;

void main() {
  // These are VM integration tests with real loopback HTTP. A widget binding
  // replaces HttpClient with a synthetic 400 response before it reaches us.
  test('HTTP body interruption, two pages and reopening preserve account evidence', () async {
    final h = await _AccountHarness.open();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final wire = _wire();
      final first = Map<String, dynamic>.from(wire['pages'][0] as Map);
      final entries = List<Map<String, dynamic>>.from(first['changes'] as List);
      final originalSong = Map<String, dynamic>.from(entries.first['payload'] as Map);
      // Real receiver limit=50: the first page must fill that limit to have_more.
      for (var index = 0; index < 43; index++) {
        entries.add({'change_seq': 15 + index, 'entity_type': 'SONG',
          'entity_id': _song, 'revision': 3 + index, 'operation': 'UPSERT',
          'payload': {...originalSong, 'revision': 3 + index, 'note': 'page $index'}});
      }
      first.addAll({'changes': entries, 'next_seq': 57, 'head_seq': 60, 'has_more': true});
      final tail = [
        for (var index = 0; index < 3; index++)
          {...Map<String, dynamic>.from(wire['pages'][1]['changes'][index] as Map),
            'change_seq': 58 + index},
      ];
      final afterCapture = {'change_seq': 61, 'entity_type': 'SONG',
        'entity_id': _song, 'revision': 46, 'operation': 'UPSERT',
        'payload': {...originalSong, 'revision': 46, 'note': 'later server commit'}};
      var interrupted = true;
      final requested = <int>[];
      server.listen((request) async {
        expect(request.uri.path, '/v1/sync/changes');
        expect(request.uri.queryParameters['limit'], '50');
        expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer synthetic');
        final after = int.parse(request.uri.queryParameters['after_seq']!);
        requested.add(after);
        final value = after == 7 ? first : after == 57
            ? {'after_seq': 57, 'next_seq': 61, 'head_seq': 61,
                'has_more': false, 'changes': [...tail, afterCapture]}
            : {'after_seq': 61, 'next_seq': 61, 'head_seq': 61,
                'has_more': false, 'changes': <Object?>[]};
        final bytes = utf8.encode(jsonEncode(value));
        request.response.headers.contentType = ContentType.json;
        if (interrupted) {
          request.response.contentLength = bytes.length;
          // Detach before sending headers (HttpResponse forbids detaching
          // after flush). Send fewer bytes than Content-Length then close.
          final socket = await request.response.detachSocket();
          try {
            socket.add(bytes.take(bytes.length ~/ 2).toList());
            await socket.flush();
          } finally {
            socket.destroy();
          }
        } else {
          request.response.add(bytes);
          await request.response.close();
        }
      });
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      final sender = Sender();
      ChangeFeedSyncBackend backend() => ChangeFeedSyncBackend(
        outgoing: sender, receiver: h.receiver(endpoint),
        session: () async => session, now: () => h.now,
      );
      final before = await h.tables();
      var receiving = backend();
      await expectLater(receiving.send(), throwsA(isA<AuthFailure>()));
      expect(await h.tables(), before);
      expect(await h.store.readCursor(), 7);
      expect(sender.sends, 0);
      await h.preserved();
      await h.reopen();
      expect(await h.tables(), before);

      interrupted = false;
      receiving = backend();
      await receiving.send();
      expect(await h.store.readCursor(), 57);
      expect(sender.sends, 0);
      expect(requested, [7, 7]);
      await receiving.send(); // The existing one-second scheduler delay remains.
      expect(requested, [7, 7]);
      final parent = (await h.store.readMetadata(LocalEntity.playlist, _playlist))!;
      final item = (await h.store.readMetadata(LocalEntity.playlistItem, _item))!;
      expect(parent.revision, 2);
      expect(item.revision, 2);
      expect(jsonDecode(item.serverJson!)['candidate_number'], '00123');
      expect(jsonDecode(item.serverJson!)['entry_key'], 'tj:00123');
      expect(jsonDecode(item.serverJson!)['candidate_snapshot']['title'], '수정 후보');
      expect(jsonDecode((await h.store.readMetadata(LocalEntity.recordingAsset, _recording))!
          .serverJson!)['cloud_state'], 'STORED');
      await h.preserved();
      // Discard the old receiver after its page committed, before any follow-up.
      await h.reopen();
      receiving = backend();
      await receiving.send();
      expect(requested, [7, 7, 57]);
      expect(await h.store.readCursor(), 61);
      expect(sender.sends, 1);
      expect((await h.store.readMetadata(LocalEntity.playlist, _playlist))!.tombstone, isTrue);
      expect((await h.store.readMetadata(LocalEntity.playlistItem, _item))!.tombstone, isTrue);
      expect((await h.store.readMetadata(LocalEntity.recording, _recording))!.tombstone, isFalse);
      expect(jsonDecode((await h.store.readMetadata(LocalEntity.recordingAsset, _recording))!
          .serverJson!)['cloud_state'], 'NONE');
      expect(jsonDecode((await h.store.readMetadata(LocalEntity.song, _song))!
          .serverJson!)['note'], 'later server commit');
      await h.preserved();
      final committed = await h.tables();
      await h.reopen();
      receiving = backend();
      await receiving.send();
      expect(requested, [7, 7, 57, 61]);
      expect((await h.tables())['metadata_copies'], committed['metadata_copies']);
      await h.preserved();
      await h.assertIsolation();
    } finally {
      await server.close(force: true);
      await h.close();
    }
  });

  test('real HTTP page rolls back on SQLite failure and revoked session before retry', () async {
    final h = await _AccountHarness.open();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<void>(), release = Completer<void>();
    var delay = false;
    try {
      final wire = _wire();
      final requests = <int>[];
      server.listen((request) async {
        requests.add(int.parse(request.uri.queryParameters['after_seq']!));
        if (delay) {
          arrived.complete();
          await release.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(wire['pages'][0]));
        await request.response.close();
      });
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      await h.sql("CREATE TRIGGER fail_delta_cursor BEFORE UPDATE ON sync_cursors BEGIN SELECT RAISE(ABORT,'synthetic cursor failure'); END");
      final before = await h.tables();
      final sender = Sender();
      var receiving = ChangeFeedSyncBackend(outgoing: sender,
        receiver: h.receiver(endpoint), session: () async => session);
      await expectLater(receiving.send(), throwsA(predicate<Object>(
          (error) => error.toString().contains('synthetic cursor failure'))));
      expect(await h.tables(), before);
      expect(sender.sends, 0);
      await h.preserved();
      await h.reopen();
      expect(await h.tables(), before);
      await h.sql('DROP TRIGGER fail_delta_cursor');
      delay = true;
      var active = true;
      receiving = ChangeFeedSyncBackend(outgoing: sender,
        receiver: h.receiver(endpoint, isCurrent: () => active), session: () async => session);
      final result = receiving.send();
      final rejected = expectLater(result, throwsStateError);
      await arrived.future.timeout(const Duration(seconds: 5));
      active = false;
      release.complete();
      await rejected;
      expect(await h.tables(), before);
      expect(sender.sends, 0);
      await h.preserved();
      await h.assertIsolation();
      delay = false;
      receiving = ChangeFeedSyncBackend(outgoing: sender,
        receiver: h.receiver(endpoint), session: () async => session);
      await receiving.send();
      expect(requests, [7, 7, 7]);
      expect(await h.store.readCursor(), 14);
      expect(sender.sends, 1);
      await h.preserved();
      await h.reopen();
      expect(await h.store.readCursor(), 14);
      await h.preserved();
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      await server.close(force: true);
      await h.close();
    }
  });
}

class _AccountHarness {
  _AccountHarness(this.directory);
  final Directory directory;
  late AccountStoreManager manager;
  late AccountStore store;
  late AccountPaths paths;
  var now = DateTime.utc(2026, 9, 30);
  late Map<String, dynamic> evidence;
  late String recordingDraft;
  late String? journal;
  final audio = List<int>.generate(32, (index) => index);
  final localRecording = canonical.uid(901);

  AccountStoreManager managerFor() => AccountStoreManager(
    environment: AppEnvironment.dev, directory: () async => directory,
    temporaryDirectory: () async => directory, clock: () => now,
  );

  static Future<_AccountHarness> open() async {
    final h = _AccountHarness(await Directory.systemTemp.createTemp('sr-change-integration-'));
    h.manager = h.managerFor();
    try {
      h.store = await h.manager.openAccount(owner);
      h.paths = await AccountPaths.create(h.directory, owner, AppEnvironment.dev);
      await h.seedEvidence();
      final fixture = businessSnapshotFixture();
      await h.store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
      for (final page in fixture['pages'] as List<dynamic>) {
        await h.store.appendSnapshotPage(token, page['entity'] as String, 0, jsonEncode(page));
      }
      await h.store.verifySnapshotDownload(token);
      await h.store.applySnapshotDownload(token);
      h.evidence = await h.tables();
      expect((await h.store.pendingMutations()).any(
          (mutation) => mutation.state == 'CONFLICT'), isTrue);
      for (final name in ['song_aliases', 'mutation_mapping_holds',
        'mutation_supersessions', 'canonical_edit_intents',
        'mutation_conflict_resolutions', 'mutation_wire_requests']) {
        expect(h.evidence[name], isNotEmpty, reason: 'Nonempty real $name evidence');
      }
      h.recordingDraft = (await h.store.readMetadata(LocalEntity.recording, h.localRecording))!.localJson!;
      h.journal = await h.store.readJournal(h.localRecording);
      return h;
    } catch (_) {
      await h.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> tables() async => Map<String, dynamic>.from(
      (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map);

  ChangeFeedReceiver receiver(Uri endpoint, {bool Function()? isCurrent}) =>
      ChangeFeedReceiver(store: store,
        transport: HttpChangeFeedTransport(endpoint, allowLocalHttp: true,
            timeout: const Duration(seconds: 3)),
        isSessionCurrent: (_) => isCurrent?.call() ?? true);

  Future<void> reopen() async {
    await manager.logout();
    manager = managerFor();
    store = await manager.openAccount(owner);
  }

  Future<void> sql(String statement) async {
    await manager.logout();
    final db = AccountDatabase(NativeDatabase(await paths.databaseFile()),
        userId: owner, environment: AppEnvironment.dev);
    try {
      await db.verifyReady();
      await db.customStatement(statement);
    } finally {
      await db.close();
    }
    store = await manager.openAccount(owner);
  }

  Future<void> preserved() async {
    final after = await tables();
    for (final name in evidence.keys) {
      if (name == 'metadata_copies' || name == 'sync_cursors') {
        continue;
      }
      expect(after[name], evidence[name], reason: '$name unchanged by receiving');
    }
    final beforeRows = evidence['metadata_copies'] as List<dynamic>;
    final afterRows = after['metadata_copies'] as List<dynamic>;
    for (final dynamic row in beforeRows) {
      if (row['local_payload'] == null ||
          row['local_payload'] == row['server_payload']) {
        continue;
      }
      final dynamic current = afterRows.singleWhere((dynamic value) =>
          value['entity_type'] == row['entity_type'] && value['entity_id'] == row['entity_id']);
      // All seeded private drafts have pending requests; remote receiving is
      // never an acknowledgement of those requests.
      expect(current['local_payload'], row['local_payload']);
    }
    expect((await store.readMetadata(LocalEntity.recording, localRecording))!.localJson, recordingDraft);
    expect(await store.readJournal(localRecording), journal);
    expect(await store.readLocalAudio(localRecording), audio);
    final file = await paths.checkedFile(paths.audioPath(localRecording));
    expect(await file.length(), audio.length);
    expect(sha256.convert(await file.readAsBytes()).toString(),
        sha256.convert(audio).toString());
  }

  Future<void> assertIsolation() async {
    final other = await manager.openAccount(canonical.uid(999));
    expect(await other.readCursor(), isNull);
    expect(await other.readMetadata(LocalEntity.recording, localRecording), isNull);
    expect(await other.readMetadata(LocalEntity.song, _song), isNull);
    expect(await other.readJournal(localRecording), isNull);
    await expectLater(other.readLocalAudio(localRecording), throwsStateError);
    store = await manager.openAccount(owner);
    await preserved();
  }

  Future<void> seedEvidence() async {
    final tagId = canonical.uid(900), source = canonical.uid(902), target = canonical.uid(903);
    await store.saveEdit(LocalEdit(opId: canonical.uid(910), entity: LocalEntity.tag,
      entityId: tagId, operation: LocalOperation.create, baseRevision: 0,
      draft: {'id': tagId, 'name': 'tag'}, changes: {'id': tagId, 'name': 'tag'}));
    expect(await store.acknowledgeMutation((await store.claimMutation())!, tag(tagId)), isTrue);
    await store.saveEdit(LocalEdit(opId: canonical.uid(911), entity: LocalEntity.tag,
      entityId: tagId, operation: LocalOperation.patch, baseRevision: 1,
      draft: tag(tagId, name: 'private'), changes: {'base_revision': 1, 'name': 'private'}));
    expect(await store.deferMutation((await store.claimMutation())!, 'CONFLICT',
      'REVISION_CONFLICT', status: 409, serverSnapshot: tag(tagId, name: 'remote', revision: 2)), isTrue);
    await store.resolveMetadataConflict(expected: (await store.pendingMutations()).single,
      expectedLocalJson: (await store.readMetadata(LocalEntity.tag, tagId))!.localJson,
      replacementOpId: canonical.uid(912), choices: {'name': ConflictChoice.local});
    expect(await store.acknowledgeMutation((await store.claimMutation())!,
        tag(tagId, name: 'private', revision: 3)), isTrue);
    // Keep an unresolved conflict as well as the completed resolution ledger.
    await store.saveEdit(LocalEdit(opId: canonical.uid(917), entity: LocalEntity.tag,
      entityId: tagId, operation: LocalOperation.patch, baseRevision: 3,
      draft: tag(tagId, name: 'unresolved private', revision: 3),
      changes: {'base_revision': 3, 'name': 'unresolved private'}));
    expect(await store.deferMutation((await store.claimMutation())!, 'CONFLICT',
      'REVISION_CONFLICT', status: 409,
      serverSnapshot: tag(tagId, name: 'new remote', revision: 4)), isTrue);
    await store.saveEdit(LocalEdit(opId: canonical.uid(913), entity: LocalEntity.song,
      entityId: source, operation: LocalOperation.create, baseRevision: 0,
      draft: {...canonical.song(source), 'note': 'private source'},
      changes: {'id': source, 'source_type': 'TJ', 'source_token': 'opaque-proof', 'note': 'private source'}));
    final creating = (await store.claimMutation())!;
    await store.saveEdit(LocalEdit(opId: canonical.uid(914), entity: LocalEntity.song,
      entityId: source, operation: LocalOperation.patch, baseRevision: 0,
      draft: {...canonical.song(source), 'note': 'later private'},
      changes: {'base_revision': 0, 'note': 'later private'}));
    final draft = <String, dynamic>{...recordingWire('RecordingDraft'),
      'id': localRecording, 'song_id': source, 'note': 'private recording',
      'title_snapshot': '당시 곡명', 'artist_snapshot': '당시 가수'};
    final fields = {...draft}..removeWhere((key, _) => {
      'revision', 'updated_at', 'origin_device_id', 'link_revision',
      'lifecycle_state', 'condition_name_snapshot',
    }.contains(key));
    await store.saveEdit(LocalEdit(opId: canonical.uid(915), entity: LocalEntity.recording,
      entityId: localRecording, operation: LocalOperation.create, baseRevision: 0,
      draft: draft, changes: fields));
    expect(await store.applyCanonicalSongReceipt(creating, MutationResponse(200,
      jsonEncode({'created': false, 'canonical_song_id': target,
        'song': canonical.song(target)}))), isTrue);
    await (await paths.checkedFile(paths.audioPath(localRecording))).writeAsBytes(audio);
    await store.recordFileAndJournal(recordingId: localRecording, operationId: canonical.uid(916),
      state: FilePresence.inputPending, phase: JournalPhase.committed, pending: false,
      checksum: sha256.convert(audio).toString(), sizeBytes: audio.length, recovery: draft);
    // Freeze a real eligible request and consume one automatic retry. This may
    // be the canonical recording replacement, whose wire must also be retained.
    final first = (await store.claimMutation())!;
    expect(await store.deferMutation(first, 'RETRY', 'HTTP_503', status: 503), isTrue);
    now = (await store.retryStatus(first.mutation.opId))!.nextAttemptAt!;
    final second = (await store.claimMutation())!;
    expect(second.mutation.opId, first.mutation.opId);
    expect(await store.deferMutation(second, 'RETRY', 'HTTP_503', status: 503), isTrue);
    expect((await store.retryStatus(first.mutation.opId))!.automaticRetriesClaimed, 1);
  }

  Future<void> close() async {
    await manager.logout();
    expect(directory.path.split(Platform.pathSeparator).last, startsWith('sr-change-integration-'));
    await directory.delete(recursive: true);
  }
}
