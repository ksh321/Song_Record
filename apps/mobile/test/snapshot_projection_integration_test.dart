import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';

import 'canonical_song_store_test.dart' as canonical;
import 'change_feed_receiver_test.dart' show FeedTransport;
import 'change_payload_validation_test.dart' show songChange, recordingWire;
import 'metadata_dispatcher_test.dart' show tag;
import 'snapshot_receiver_test.dart' show FakeTransport, session;
import 'snapshot_sync_backend_test.dart' show Sender;
import 'support/business_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('initial business copy survives delta failure and reopening before send',
      initialProjectionSurvivesDeltaFailure);
  test('initial publication retains canonical and conflict resolution ledgers',
      initialProjectionPreservesResolutionEvidence);
}

Future<void> initialProjectionPreservesResolutionEvidence() async {
  const owner = '11111111-1111-4111-8111-111111111111';
  const token = '22222222-2222-4222-8222-222222222222';
  const target = '33333333-3333-4333-8333-333333333333';
  const source = '44444444-4444-4444-8444-444444444444';
  final tagId = canonical.uid(90), recId = canonical.uid(91);
  final directory = await Directory.systemTemp.createTemp('sr-snapshot-evidence-');
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => directory,
    temporaryDirectory: () async => directory,
    clock: () => DateTime.utc(2026, 9, 30),
  );
  try {
    var store = await manager.openAccount(owner);
    await store.saveEdit(LocalEdit(
      opId: canonical.uid(100), entity: LocalEntity.tag, entityId: tagId,
      operation: LocalOperation.create, baseRevision: 0,
      draft: {'id': tagId, 'name': 'tag'},
      changes: {'id': tagId, 'name': 'tag'},
    ));
    expect(await store.acknowledgeMutation((await store.claimMutation())!, tag(tagId)), isTrue);
    await store.saveEdit(LocalEdit(
      opId: canonical.uid(101), entity: LocalEntity.tag, entityId: tagId,
      operation: LocalOperation.patch, baseRevision: 1,
      draft: tag(tagId, name: 'local'), changes: {'base_revision': 1, 'name': 'local'},
    ));
    expect(await store.deferMutation(
      (await store.claimMutation())!, 'CONFLICT', 'REVISION_CONFLICT', status: 409,
      serverSnapshot: tag(tagId, name: 'remote', revision: 2),
    ), isTrue);
    await store.resolveMetadataConflict(
      expected: (await store.pendingMutations()).single,
      expectedLocalJson: (await store.readMetadata(LocalEntity.tag, tagId))!.localJson,
      replacementOpId: canonical.uid(102), choices: {'name': ConflictChoice.local},
    );
    expect(await store.acknowledgeMutation(
      (await store.claimMutation())!, tag(tagId, name: 'local', revision: 3),
    ), isTrue);
    await store.saveEdit(LocalEdit(
      opId: canonical.uid(110), entity: LocalEntity.song, entityId: source,
      operation: LocalOperation.create, baseRevision: 0,
      draft: {...canonical.song(source), 'note': 'source private'},
      changes: {'id': source, 'source_type': 'TJ', 'source_token': 'opaque-proof',
        'note': 'source private'},
    ));
    final request = (await store.claimMutation())!;
    await store.saveEdit(LocalEdit(
      opId: canonical.uid(111), entity: LocalEntity.song, entityId: source,
      operation: LocalOperation.patch, baseRevision: 0,
      draft: {...canonical.song(source), 'note': 'later private edit'},
      changes: {'base_revision': 0, 'note': 'later private edit'},
    ));
    final recording = <String, dynamic>{
      ...recordingWire('RecordingDraft'), 'id': recId, 'song_id': source,
      'note': 'recording private',
    };
    final recordingFields = {...recording}..removeWhere((key, _) => {
      'revision', 'updated_at', 'origin_device_id', 'link_revision',
      'lifecycle_state', 'condition_name_snapshot',
    }.contains(key));
    await store.saveEdit(LocalEdit(
      opId: canonical.uid(112), entity: LocalEntity.recording, entityId: recId,
      operation: LocalOperation.create, baseRevision: 0,
      draft: recording, changes: recordingFields,
    ));
    expect(await store.applyCanonicalSongReceipt(request, MutationResponse(200,
      jsonEncode({'created': false, 'canonical_song_id': target,
        'song': canonical.song(target)}),
    )), isTrue);
    Future<Map<dynamic, dynamic>> tables() async =>
        (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
    final before = await tables();
    for (final name in [
      'song_aliases', 'mutation_mapping_holds', 'mutation_supersessions',
      'canonical_edit_intents', 'mutation_conflict_resolutions', 'mutation_wire_requests',
    ]) {
      expect(before[name], isNotEmpty, reason: 'Exercise real $name evidence');
    }
    final sourceDraft = (await store.readMetadata(LocalEntity.song, source))!.localJson;
    final recordingDraft = (await store.readMetadata(LocalEntity.recording, recId))!.localJson;
    final fixture = businessSnapshotFixture();
    replaceBusinessSnapshotRows(fixture, 'SONG', [
      {...canonical.song(target, revision: 3), 'user_id': owner},
    ]);
    await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
    for (final page in fixture['pages'] as List) {
      await store.appendSnapshotPage(token, page['entity'] as String, 0, jsonEncode(page));
    }
    await store.verifySnapshotDownload(token);
    await store.applySnapshotDownload(token);
    Future<void> preserved() async {
      final after = await tables();
      for (final name in before.keys) {
        if (name == 'metadata_copies' || name == 'sync_cursors' ||
            (name as String).startsWith('snapshot_')) {
          continue;
        }
        expect(after[name], before[name], reason: 'Preserve $name');
      }
      expect((await store.readMetadata(LocalEntity.song, target))!.revision, 3);
      expect((await store.readMetadata(LocalEntity.song, source))!.localJson, sourceDraft);
      expect((await store.readMetadata(LocalEntity.recording, recId))!.localJson, recordingDraft);
      expect(await store.readCursor(), 7);
    }
    await preserved();
    await manager.logout();
    store = await manager.openAccount(owner);
    await store.applySnapshotDownload(token);
    await preserved();
  } finally {
    await manager.logout();
    expect(directory.path.split(Platform.pathSeparator).last,
        startsWith('sr-snapshot-evidence-'));
    await directory.delete(recursive: true);
  }
}

// Also exercised by the controller's narrow snapshot business test target.
Future<void> initialProjectionSurvivesDeltaFailure() async {
  const owner = '11111111-1111-4111-8111-111111111111';
  const token = '22222222-2222-4222-8222-222222222222';
  const song = '33333333-3333-4333-8333-333333333333';
  const operation = '44444444-4444-4444-8444-444444444444';
  const editOperation = '55555555-5555-4555-8555-555555555555';
  var now = DateTime.utc(2026, 9, 30);
  final directory = await Directory.systemTemp.createTemp('sr-snapshot-delta-');
  AccountStoreManager managerFor() => AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => directory,
    temporaryDirectory: () async => directory,
    clock: () => now,
  );
  var manager = managerFor();
  try {
    var store = await manager.openAccount(owner);
    final draft = songChange(song, 1, title: 'offline title');
    await store.saveEdit(LocalEdit(
      opId: editOperation,
      entity: LocalEntity.song,
      entityId: song,
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: draft,
      changes: draft,
    ));
    Future<Map<dynamic, dynamic>> tables() async =>
        (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
    final original = await tables();
    final fixture = businessSnapshotFixture();
    final snapshots = FakeTransport();
    snapshots.respond = (request) async {
      expect(await store.hasCompleteBaseline(), isFalse);
      if (request.method == 'POST') {
        expect(request.operationId, operation);
        return SnapshotHttpResponse(202, jsonEncode({
          'operation_id': operation,
          'snapshot_token': token,
          'status': 'BUILDING',
          'status_url': '/v1/sync/snapshots/$token',
        }));
      }
      final entity = request.query['entity'];
      return SnapshotHttpResponse(200, jsonEncode(
        entity == null ? fixture['manifest'] :
            (fixture['pages'] as List).singleWhere(
              (dynamic page) => page['entity'] == entity,
            ),
      ));
    };
    final changes = FeedTransport();
    final sender = Sender();
    Map<dynamic, dynamic>? beforeFailedDelta;
    var failDelta = true;
    changes.respond = (request) async {
      expect(request.after, 7);
      expect(await store.hasCompleteBaseline(), isTrue);
      expect(await store.readSnapshotResume(), isNull);
      final copy = (await store.readMetadata(LocalEntity.song, song))!;
      expect(copy.revision, 1);
      expect(jsonDecode(copy.serverJson!)['note'], '한글 🎵');
      expect(copy.localJson, canonicalJson(draft));
      final view = await store.snapshotMetadataView(
        LocalEntity.song, song, expectedToken: token,
      );
      expect(view.baseline!.token, token);
      expect(view.baseline!.entry!.payload['note'], '한글 🎵');
      expect(view.cached!.revision, copy.revision);
      expect(view.cached!.serverJson, copy.serverJson);
      expect(view.cached!.localJson, canonicalJson(draft));
      expect((await tables())['local_mutations'], original['local_mutations']);
      expect(sender.sends, 0);
      if (failDelta) {
        beforeFailedDelta = await tables();
        return const ChangeFeedResponse(503, '{}');
      }
      return ChangeFeedResponse(200, jsonEncode({
        'after_seq': 7, 'next_seq': 8, 'head_seq': 8, 'has_more': false,
        'changes': [{
          'change_seq': 8, 'entity_type': 'SONG', 'entity_id': song,
          'revision': 2, 'operation': 'UPSERT',
          'payload': songChange(song, 2, title: 'later delta title'),
        }],
      }));
    };
    SnapshotSyncBackend backendFor() => SnapshotSyncBackend(
      receiver: SnapshotReceiver(
        store: store, transport: snapshots,
        newOperationId: () => operation, clock: () => now,
      ),
      session: () async => session,
      now: () => now,
      outgoing: ChangeFeedSyncBackend(
        outgoing: sender,
        receiver: ChangeFeedReceiver(
          store: store, transport: changes,
          isSessionCurrent: (value) => identical(value, session),
        ),
        session: () async => session,
        now: () => now,
      ),
    );
    var backend = backendFor();
    // Each call performs one initial request; only publication reaches delta.
    final initialSteps = (fixture['pages'] as List).length + 2;
    for (var step = 0; step < initialSteps; step++) {
      await backend.send();
      expect(changes.calls, 0);
      expect(sender.sends, 0);
      now = now.add(const Duration(seconds: 1));
    }
    await expectLater(backend.send(), throwsA(isA<AuthFailure>()));
    expect(changes.calls, 1);
    expect(sender.sends, 0);
    expect(await store.readCursor(), 7);
    expect(await tables(), beforeFailedDelta);
    final raw = (await store.snapshotBaselineRecord('SONG', song))!
        .entry!.canonicalPayload;
    final snapshotRequests = snapshots.requests.length;
    await manager.logout();
    manager = managerFor();
    store = await manager.openAccount(owner);
    expect(await tables(), beforeFailedDelta);
    backend = backendFor();
    await expectLater(backend.send(), throwsA(isA<AuthFailure>()));
    expect(changes.calls, 2);
    expect(sender.sends, 0);
    expect(snapshots.requests, hasLength(snapshotRequests));
    expect(await tables(), beforeFailedDelta);
    failDelta = false;
    await backend.send();
    expect(changes.calls, 3);
    expect(sender.sends, 1);
    expect(await store.readCursor(), 8);
    final copy = (await store.readMetadata(LocalEntity.song, song))!;
    expect(copy.revision, 2);
    expect(jsonDecode(copy.serverJson!)['title'], 'later delta title');
    expect(copy.localJson, canonicalJson(draft));
    expect((await store.snapshotBaselineRecord('SONG', song))!
        .entry!.canonicalPayload, raw);
    final after = await tables();
    for (final name in original.keys) {
      if (name == 'metadata_copies' || name == 'sync_cursors' ||
          (name as String).startsWith('snapshot_')) {
        continue;
      }
      expect(after[name], original[name], reason: 'Preserve $name');
    }
  } finally {
    await manager.logout();
    expect(directory.path.split(Platform.pathSeparator).last,
        startsWith('sr-snapshot-delta-'));
    await directory.delete(recursive: true);
  }
}
