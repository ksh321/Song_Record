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
import 'package:song_record/core/sync/dependency_planner.dart';
import 'package:song_record/core/sync/metadata_dispatcher.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

String uid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

const timestamp = '2026-09-29T00:00:00Z';

final class ReceiptTransport implements MutationTransport {
  ReceiptTransport(this.respond);
  final Future<MutationResponse> Function(MutationRequest) respond;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() requireActive,
  ) {
    requireActive();
    return respond(request);
  }
}

Map<String, Object?> song(String id, {int revision = 2}) => {
  'id': id,
  'revision': revision,
  'updated_at': timestamp,
  'source_type': 'TJ',
  'tj_number': '12345',
  'title': 'server title',
  'artist': 'server artist',
  'version_code': 'NORMAL',
  'tier': null,
  'note': 'server note',
  'lifecycle_state': 'ACTIVE',
  'representative_key_mode': null,
  'representative_key_shift': null,
  'representative_recording_id': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final owner = uid(1);
  final source = uid(10);
  final canonical = uid(11);
  final createOp = uid(110);

  late Directory directory;
  late AccountStoreManager manager;
  late AccountStore store;
  void Function()? onClock;

  Future<AuthSession> session() async => AuthSession(
    userId: owner,
    deviceId: uid(2),
    accessToken: 'test-access',
    refreshToken: 'test-refresh',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  );

  MutationResponse receipt() => MutationResponse(
    200,
    ' \n${jsonEncode({'created': false, 'canonical_song_id': canonical, 'song': song(canonical)})}\n ',
  );

  Future<AccountDatabase> raw() async {
    final paths = await AccountPaths.create(
      directory,
      owner,
      AppEnvironment.dev,
    );
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  Future<Map<String, dynamic>> tables() async {
    final export =
        jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
    return export['tables'] as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> rows(
    Map<String, dynamic> snapshot,
    String table,
  ) => (snapshot[table] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Future<void> insertCopy({
    required LocalEntity entity,
    required String id,
    required int revision,
    required Map<String, Object?>? server,
    required Map<String, Object?>? local,
    bool tombstone = false,
  }) async {
    final db = await raw();
    try {
      await db.customStatement(
        '''
          INSERT INTO metadata_copies(
            user_id,entity_type,entity_id,server_revision,
            server_payload,local_payload,tombstone,updated_at
          ) VALUES(?,?,?,?,?,?,?,1)
        ''',
        [
          owner,
          entity.code,
          id,
          revision,
          server == null ? null : canonicalJson(server),
          local == null ? null : canonicalJson(local),
          tombstone ? 1 : 0,
        ],
      );
    } finally {
      await db.close();
    }
  }

  Future<void> saveSource() => store.saveEdit(
    LocalEdit(
      opId: createOp,
      entity: LocalEntity.song,
      entityId: source,
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: {
        ...song(source),
        'revision': 0,
        'note': 'source private',
        'tier': 'SOURCE_PRIVATE',
        'representative_key_shift': 4,
      },
      changes: {
        'id': source,
        'source_type': 'TJ',
        'source_token': 'opaque-server-proof',
        'note': 'source private',
      },
    ),
  );

  Future<MutationRequest> seed({
    int? canonicalRevision = 5,
    bool tombstone = false,
    bool nullDraft = false,
  }) async {
    await saveSource();
    // Only the SONG CREATE exists at this point.
    final request = (await store.claimMutation())!;

    if (canonicalRevision != null) {
      await insertCopy(
        entity: LocalEntity.song,
        id: canonical,
        revision: canonicalRevision,
        server: canonicalRevision == 0
            ? null
            : song(canonical, revision: canonicalRevision),
        local: nullDraft
            ? null
            : {
                ...song(canonical, revision: canonicalRevision),
                'note': 'canonical private',
                'tier': 'CANONICAL_PRIVATE',
              },
        tombstone: tombstone,
      );
    }
    return request;
  }

  Future<void> relatedEdits() async {
    for (final entry in [
      (source, uid(111), 0, 'source later'),
      (canonical, uid(112), 5, 'canonical later'),
    ]) {
      await store.saveEdit(
        LocalEdit(
          opId: entry.$2,
          entity: LocalEntity.song,
          entityId: entry.$1,
          operation: LocalOperation.patch,
          baseRevision: entry.$3,
          draft: {
            ...song(entry.$1, revision: entry.$3),
            'note': entry.$4,
            'representative_key_shift': 7,
          },
          changes: {'base_revision': entry.$3, 'note': entry.$4},
        ),
      );
    }

    // 30: ordinary source reference; PATCH omits song_id.
    // 31: explicit null local selection; old server still references source.
    // 32: another local selection; old server still references source.
    // 33: playlist reference.
    // 34: wholly unrelated.
    // 35: tombstoned reference; its draft must not be rewritten.
    for (final n in [30, 31, 32, 33, 34, 35, 36]) {
      final entity = n == 33 ? LocalEntity.playlistItem : LocalEntity.recording;
      final Object? selected = switch (n) {
        31 => null,
        32 || 34 => uid(90),
        36 => canonical,
        _ => source,
      };
      final server = <String, Object?>{
        'id': uid(n),
        'song_id': n == 34 ? uid(90) : (n == 36 ? canonical : source),
        'revision': 3,
        'note': 'server-$n',
      };
      final draft = <String, Object?>{
        ...server,
        'song_id': selected,
        'note': 'private-$n',
        'unknown_local_field': {'keep': n},
      };
      await insertCopy(
        entity: entity,
        id: uid(n),
        revision: 3,
        server: server,
        local: draft,
        tombstone: n == 35,
      );
      if (n == 35) continue;
      await store.saveEdit(
        LocalEdit(
          opId: uid(200 + n),
          entity: entity,
          entityId: uid(n),
          operation: LocalOperation.patch,
          baseRevision: 3,
          draft: draft,
          changes: {'base_revision': 3, 'note': 'private-$n'},
        ),
      );
    }

    // Already attempted recording PATCH: preserve its wire and retry budget.
    final pending = await store.pendingMutations();
    final recording = pending.singleWhere((m) => m.opId == uid(230));
    final frozen = MutationRequest.prepare(recording)!;
    final db = await raw();
    try {
      await db.customStatement(
        '''
          INSERT INTO mutation_wire_requests(
            op_id,contract_version,http_method,relative_path,body_json,wire_hash
          ) VALUES(?,?,?,?,?,?)
        ''',
        [
          recording.opId,
          MutationRequest.contract,
          frozen.method,
          frozen.path,
          frozen.body,
          frozen.hash,
        ],
      );
      await db.customStatement(
        '''
          UPDATE local_mutations
          SET queue_state='RETRY',attempt_count=2,next_attempt_at=9999999999999
          WHERE op_id=?
        ''',
        [recording.opId],
      );
      await db.customStatement(
        '''
          UPDATE mutation_retry_controls
          SET automatic_retries_claimed=1,retry_mode='AUTO',
              last_attempt_kind='AUTO'
          WHERE op_id=?
        ''',
        [recording.opId],
      );
    } finally {
      await db.close();
    }

    final paths = await AccountPaths.create(
      directory,
      owner,
      AppEnvironment.dev,
    );
    final file = await paths.checkedFile(paths.audioPath(uid(30)));
    await file.parent.create(recursive: true);
    final bytes = [7, 8, 9, 10];
    await file.writeAsBytes(bytes);
    await store.recordFileAndJournal(
      recordingId: uid(30),
      operationId: uid(330),
      state: FilePresence.saved,
      phase: JournalPhase.committed,
      pending: false,
      checksum: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      recovery: {'song_id': source, 'note': 'journal private'},
    );
  }

  Future<void> saveSongPatch(String target, String opId, int revision) =>
      store.saveEdit(
        LocalEdit(
          opId: opId,
          entity: LocalEntity.song,
          entityId: target,
          operation: LocalOperation.patch,
          baseRevision: revision,
          draft: {
            ...song(target, revision: revision),
            'note': opId,
          },
          changes: {'base_revision': revision, 'note': opId},
        ),
      );

  Future<void> saveUnrelatedTag() => store.saveEdit(
    LocalEdit(
      opId: uid(800),
      entity: LocalEntity.tag,
      entityId: uid(80),
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: {'id': uid(80), 'name': 'unrelated'},
      changes: {'id': uid(80), 'name': 'unrelated'},
    ),
  );

  // Fixture-only evidence of an explicit resolution. Production code in this
  // patch never releases a hold or creates a supersession.
  Future<void> releaseHolds(String opId) async {
    final db = await raw();
    try {
      await db.customStatement(
        '''
          UPDATE mutation_mapping_holds
          SET released_at=2,release_evidence='{"fixture":"explicit resolution"}'
          WHERE op_id=? AND released_at IS NULL
        ''',
        [opId],
      );
    } finally {
      await db.close();
    }
  }

  Future<void> addSupersession(String original, String replacement) async {
    final db = await raw();
    try {
      await db.customStatement(
        '''
          INSERT INTO mutation_supersessions(
            original_op_id,replacement_op_id,mapping_source_id,user_id,
            order_root_op_id,logical_order,created_at
          )
          SELECT m.op_id,?,?,?,
            COALESCE(s.order_root_op_id,m.op_id),
            COALESCE(s.logical_order,m.rowid),1
          FROM local_mutations m
          LEFT JOIN mutation_supersessions s ON s.replacement_op_id=m.op_id
          WHERE m.op_id=?
        ''',
        [replacement, source, owner, original],
      );
    } finally {
      await db.close();
    }
  }

  Future<void> seedDirectSupersession({required bool release}) async {
    final request = await seed();
    await saveSongPatch(source, uid(701), 0);
    expect(await store.applyCanonicalSongReceipt(request, receipt()), isTrue);

    // Physical order: original, younger canonical edit, replacement.
    await saveSongPatch(canonical, uid(702), 5);
    await saveSongPatch(canonical, uid(703), 5);
    await addSupersession(uid(701), uid(703));

    if (release) await releaseHolds(uid(701));
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sr-canonical-store-');
    onClock = null;
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
      clock: () {
        final callback = onClock;
        onClock = null;
        callback?.call();
        return DateTime.utc(2026, 9, 29);
      },
    );
    store = await manager.openAccount(owner);
  });

  tearDown(() async {
    await manager.logout();
    await directory.delete(recursive: true);
  });

  test(
    'dispatcher maps receipt before next claim and preserves held edits',
    () async {
      await saveSource();
      await saveSongPatch(source, uid(111), 0);
      await saveUnrelatedTag();
      final before = await tables();
      final sent = <String>[];
      final dispatcher = MetadataDispatcher(
        store,
        ReceiptTransport((request) async {
          sent.add(request.mutation.opId);
          if (request.mutation.opId == createOp) return receipt();
          expect(request.mutation.opId, uid(800));
          return MutationResponse(
            201,
            jsonEncode({
              'id': uid(80),
              'name': 'unrelated',
              'revision': 1,
              'archived_at': null,
              'updated_at': timestamp,
            }),
          );
        }),
        session,
      );
      expect(await dispatcher.dispatch(), 2);
      expect(sent, [createOp, uid(800)]);
      final after = await tables();
      expect(
        rows(after, 'song_aliases').single['receipt_body'],
        receipt().body,
      );
      expect(rows(after, 'canonical_edit_intents'), isNotEmpty);
      final original = rows(before, 'local_mutations');
      final current = rows(after, 'local_mutations');
      for (final old in original.where((row) => row['op_id'] == uid(111))) {
        expect(current.singleWhere((row) => row['op_id'] == old['op_id']), old);
      }
      expect(
        current.singleWhere((row) => row['op_id'] == createOp)['queue_state'],
        'ACKED',
      );
      expect(
        rows(
          after,
          'metadata_copies',
        ).singleWhere((row) => row['entity_id'] == source),
        rows(
          before,
          'metadata_copies',
        ).singleWhere((row) => row['entity_id'] == source),
      );
      expect(rows(after, 'mutation_mapping_holds').single['op_id'], uid(111));
      expect(await dispatcher.dispatch(), 0);
      expect(sent, [createOp, uid(800)]);
    },
  );

  for (final scenario in [
    'wrong-status',
    'bad-envelope',
    'manual',
    'same-id',
  ]) {
    test('dispatcher preserves source for $scenario receipt', () async {
      await saveSource();
      final before = await tables();
      final snapshot = song(scenario == 'same-id' ? source : canonical);
      if (scenario == 'manual') {
        snapshot['source_type'] = 'MANUAL';
        snapshot['tj_number'] = null;
      }
      final response = MutationResponse(
        scenario == 'wrong-status' ? 201 : 200,
        jsonEncode({
          'created': false,
          'canonical_song_id': scenario == 'bad-envelope'
              ? uid(99)
              : snapshot['id'],
          'song': snapshot,
        }),
      );
      final dispatcher = MetadataDispatcher(
        store,
        ReceiptTransport((_) async => response),
        session,
      );
      expect(await dispatcher.dispatch(), 0);
      final after = await tables();
      expect(after['song_aliases'], isEmpty);
      expect(after['canonical_edit_intents'], isEmpty);
      expect(after['metadata_copies'], before['metadata_copies']);
      final mutation = (await store.pendingMutations()).single;
      expect(mutation.state, scenario == 'same-id' ? 'CONFLICT' : 'RETRY');
      expect(mutation.attemptCount, 1);
    });
  }

  test(
    'dispatcher cannot map an attempt superseded during transport',
    () async {
      await saveSource();
      final dispatcher = MetadataDispatcher(
        store,
        ReceiptTransport((request) async {
          await store.deferMutation(request, 'RETRY', 'TEST_SUPERSEDED');
          return receipt();
        }),
        session,
      );
      expect(await dispatcher.dispatch(), 0);
      expect((await tables())['song_aliases'], isEmpty);
      expect((await store.pendingMutations()).single.state, 'RETRY');
    },
  );

  test(
    'atomic mapping preserves drafts, wire, budgets, files and evidence',
    () async {
      final request = await seed();
      await relatedEdits();
      final before = await tables();
      final response = receipt();

      expect(await store.applyCanonicalSongReceipt(request, response), isTrue);
      final after = await tables();

      final alias = rows(after, 'song_aliases').single;
      expect(alias['receipt_body'], response.body);
      expect(alias['receipt_status'], 200);
      expect(alias['source_song_id'], source);
      expect(alias['canonical_song_id'], canonical);

      Map<String, dynamic> metadata(Map<String, dynamic> value, String id) =>
          rows(
            value,
            'metadata_copies',
          ).singleWhere((row) => row['entity_id'] == id);

      // Source metadata is untouched. A higher canonical baseline and its
      // local draft are also untouched.
      expect(metadata(after, source), metadata(before, source));
      expect(metadata(after, canonical), metadata(before, canonical));

      for (final n in [30, 31, 32, 33, 34, 35, 36]) {
        final oldRow = metadata(before, uid(n));
        final newRow = metadata(after, uid(n));
        final oldDraft = jsonDecode(
          oldRow['local_payload'] as String,
        ) as Map<String, dynamic>;
        final newDraft = jsonDecode(
          newRow['local_payload'] as String,
        ) as Map<String, dynamic>;
        expect(newDraft, {
          ...oldDraft,
          if (n == 30 || n == 33) 'song_id': canonical,
        });
        expect(newRow['server_payload'], oldRow['server_payload']);
        expect(newRow['server_revision'], oldRow['server_revision']);
        expect(newRow['tombstone'], oldRow['tombstone']);
      }

      final oldMutations = rows(before, 'local_mutations');
      final newMutations = rows(after, 'local_mutations');
      expect(newMutations.length, oldMutations.length);
      for (final old in oldMutations) {
        final current = newMutations.singleWhere(
          (m) => m['op_id'] == old['op_id'],
        );
        if (old['op_id'] == createOp) {
          expect(current, {
            ...old,
            'queue_state': 'ACKED',
            'server_response': response.body,
            'updated_at': current['updated_at'],
          });
        } else {
          expect(current, old);
        }
      }

      for (final table in [
        'mutation_wire_requests',
        'local_recording_files',
        'recording_journals',
        'sync_cursors',
        'import_jobs',
        'import_items',
      ]) {
        expect(after[table], before[table], reason: table);
      }
      expect(after['mutation_supersessions'], isEmpty);

      final oldControls = rows(before, 'mutation_retry_controls');
      final newControls = rows(after, 'mutation_retry_controls');
      for (final old in oldControls) {
        final current = newControls.singleWhere(
          (r) => r['op_id'] == old['op_id'],
        );
        expect(
          current,
          old['op_id'] == createOp ? {...old, 'retry_mode': 'BLOCKED'} : old,
        );
      }

      final holds = rows(after, 'mutation_mapping_holds');
      expect(
        holds.map((h) => h['op_id']),
        unorderedEquals([
          uid(111),
          uid(112),
          uid(230),
          uid(231),
          uid(232),
          uid(233),
        ]),
      );
      expect(holds.every((h) => h['disposition'] == 'BLOCK'), isTrue);
      expect(holds.every((h) => h['released_at'] == null), isTrue);

      final intents = rows(after, 'canonical_edit_intents');
      final values = intents.singleWhere((i) => i['kind'] == 'SONG_VALUES');
      final evidence =
          jsonDecode(values['evidence_json'] as String) as Map<String, dynamic>;
      expect(evidence['source_before'], metadata(before, source));
      expect(evidence['canonical_before'], metadata(before, canonical));
      expect(evidence['mapping_request_body'], request.body);

      final patchIntent = intents.singleWhere(
        (i) => i['intent_key'] == 'reference:RECORDING:${uid(30)}',
      );
      final patchEvidence = jsonDecode(
        patchIntent['evidence_json'] as String,
      ) as Map<String, dynamic>;
      final captured =
          (patchEvidence['mutations_before'] as List).single
              as Map<String, dynamic>;
      expect(
        jsonDecode(captured['payload'] as String),
        isNot(contains('song_id')),
      );

      expect(await store.readLocalAudio(uid(30)), [7, 8, 9, 10]);
      expect(await store.readCursor(), isNull);

      final db = await raw();
      try {
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );

  for (final variant in [
    (revision: null, tombstone: false, nullDraft: false),
    (revision: 0, tombstone: false, nullDraft: false),
    (revision: 1, tombstone: false, nullDraft: false),
    (revision: 1, tombstone: false, nullDraft: true),
    (revision: 2, tombstone: false, nullDraft: false),
    (revision: 5, tombstone: false, nullDraft: false),
    (revision: 5, tombstone: true, nullDraft: false),
  ]) {
    test('canonical metadata preservation: $variant', () async {
      final request = await seed(
        canonicalRevision: variant.revision,
        tombstone: variant.tombstone,
        nullDraft: variant.nullDraft,
      );
      final before = await store.readMetadata(LocalEntity.song, canonical);

      expect(await store.applyCanonicalSongReceipt(request, receipt()), isTrue);
      final after = (await store.readMetadata(LocalEntity.song, canonical))!;

      if (before == null) {
        expect(after.revision, 2);
        expect(after.serverJson, canonicalJson(song(canonical)));
        expect(after.localJson, canonicalJson(song(canonical)));
      } else {
        expect(after.localJson, before.localJson);
        expect(after.tombstone, before.tombstone);
        if (before.tombstone || before.revision >= 2) {
          expect(after.revision, before.revision);
          expect(after.serverJson, before.serverJson);
        } else {
          expect(after.revision, 2);
          expect(after.serverJson, canonicalJson(song(canonical)));
        }
      }
    });
  }

  test(
    'repeated receipt has no writes, including after a later local edit',
    () async {
      final request = await seed();
      expect(await store.applyCanonicalSongReceipt(request, receipt()), isTrue);

      await store.saveEdit(
        LocalEdit(
          opId: uid(900),
          entity: LocalEntity.song,
          entityId: canonical,
          operation: LocalOperation.patch,
          baseRevision: 5,
          draft: {...song(canonical, revision: 5), 'note': 'later draft'},
          changes: {'base_revision': 5, 'note': 'later draft'},
        ),
      );
      final before = await tables();
      expect(
        await store.applyCanonicalSongReceipt(request, receipt()),
        isFalse,
      );
      expect(await tables(), before);
      // This does not claim saveEdit-to-mapping-intent integration exists.
    },
  );

  test('an unclaimed CREATE cannot receive a fake ACK', () async {
    await saveSource();
    final pending = (await store.pendingMutations()).single;
    final unclaimed = MutationRequest.prepare(pending)!;
    final before = await tables();

    expect(
      await store.applyCanonicalSongReceipt(unclaimed, receipt()),
      isFalse,
    );
    expect(await tables(), before);
  });

  test('wrong attempt or changed frozen body cannot write', () async {
    final request = await seed();
    final before = await tables();
    for (final candidate in [
      MutationRequest(
        mutation: request.mutation,
        method: request.method,
        path: request.path,
        body: request.body,
        attempt: request.attempt + 1,
      ),
      MutationRequest(
        mutation: request.mutation,
        method: request.method,
        path: request.path,
        body: '${request.body} ',
        attempt: request.attempt,
      ),
    ]) {
      expect(
        await store.applyCanonicalSongReceipt(candidate, receipt()),
        isFalse,
      );
      expect(await tables(), before);
    }
  });

  test(
    'decoder rejection rolls back without accepting a partial snapshot',
    () async {
      final request = await seed();
      final before = await tables();
      final incomplete = song(canonical)..remove('representative_key_shift');

      await expectLater(
        store.applyCanonicalSongReceipt(
          request,
          MutationResponse(
            200,
            jsonEncode({
              'created': false,
              'canonical_song_id': canonical,
              'song': incomplete,
            }),
          ),
        ),
        throwsFormatException,
      );
      expect(await tables(), before);
    },
  );

  test('expired account lease cannot map a response', () async {
    final request = await seed();
    final oldStore = store;
    store = await manager.openAccount(uid(2));
    final otherBefore = await tables();

    await expectLater(
      oldStore.applyCanonicalSongReceipt(request, receipt()),
      throwsStateError,
    );
    expect(await tables(), otherBefore);

    store = await manager.openAccount(owner);
    final reopenedBefore = await tables();
    expect(await store.applyCanonicalSongReceipt(request, receipt()), isFalse);
    expect(await tables(), reopenedBefore);
  });

  test(
    'canonical outgoing alias is rejected without flattening a chain',
    () async {
      final request = await seed();
      await insertCopy(
        entity: LocalEntity.song,
        id: uid(12),
        revision: 1,
        server: song(uid(12), revision: 1),
        local: song(uid(12), revision: 1),
      );
      final db = await raw();
      try {
        await db.customStatement(
          '''
          INSERT INTO local_mutations(
            op_id,user_id,entity_type,entity_id,operation,base_revision,
            payload,request_hash,queue_state,created_at,updated_at
          ) VALUES(?,?,'SONG',?,'CREATE',0,?,?,'ACKED',1,1)
        ''',
          [
            uid(500),
            owner,
            canonical,
            jsonEncode({
              'id': canonical,
              'source_type': 'TJ',
              'source_token': 'synthetic',
            }),
            'a' * 64,
          ],
        );
        await db.customStatement(
          '''
          INSERT INTO song_aliases(
            source_song_id,canonical_song_id,user_id,mapping_op_id,
            receipt_status,receipt_body,created_at
          ) VALUES(?,?,?,?,200,?,1)
        ''',
          [
            canonical,
            uid(12),
            owner,
            uid(500),
            jsonEncode({
              'created': false,
              'canonical_song_id': uid(12),
              'song': song(uid(12), revision: 1),
            }),
          ],
        );
      } finally {
        await db.close();
      }

      final before = await tables();
      await expectLater(
        store.applyCanonicalSongReceipt(request, receipt()),
        throwsStateError,
      );
      expect(await tables(), before);
    },
  );

  for (final disposition in ['BLOCK', 'REPLAY_ORIGINAL']) {
    test('$disposition blocks frozen retry, manual grant and deadlines '
        'without spending budget; unrelated work continues', () async {
      final mappingRequest = await seed();
      final head = uid(710);
      await saveSongPatch(canonical, head, 5);

      // Before mapping, the canonical target is independent of the source.
      final frozen = (await store.claimMutation())!;
      expect(frozen.mutation.opId, head);
      expect(
        await store.deferMutation(frozen, 'RETRY', 'NETWORK_UNAVAILABLE'),
        isTrue,
      );

      expect(
        await store.applyCanonicalSongReceipt(mappingRequest, receipt()),
        isTrue,
      );

      if (disposition == 'REPLAY_ORIGINAL') {
        await releaseHolds(head);
        final db = await raw();
        try {
          await db.customStatement(
            '''
                INSERT INTO mutation_mapping_holds(
                  op_id,mapping_source_id,user_id,reason,
                  disposition,created_at
                ) VALUES(?,?,?,'FIXTURE_REPLAY','REPLAY_ORIGINAL',1)
              ''',
            [head, source, owner],
          );
        } finally {
          await db.close();
        }
      }

      await saveSongPatch(canonical, uid(711), 5);
      await saveSongPatch(source, uid(712), 0);

      final before = await tables();
      final status = (await store.retryStatus(head))!;
      expect(status.mappingEligible, isFalse);
      expect(status.canRetryManually, isFalse);
      expect(status.attemptCount, 1);
      expect(status.automaticRetriesClaimed, 0);

      final plan = const DependencyPlanner().plan(
        await store.dispatchSnapshot(),
      );
      expect(plan.ready, isEmpty);
      expect(plan.waiting[head]!.reason, DispatchWaitReason.mappingBlocked);
      expect(
        plan.waiting[uid(711)]!.reason,
        DispatchWaitReason.earlierMutation,
      );
      expect(
        plan.waiting[uid(712)]!.reason,
        DispatchWaitReason.earlierMutation,
      );

      expect(await store.retryMutation(head, expectedAttempt: 1), isFalse);
      expect(await store.nextAutomaticRetryAt(), isNull);
      expect(await store.nextDispatchAt(), isNull);
      expect(await store.claimMutation(), isNull);
      expect(await tables(), before);

      await saveUnrelatedTag();
      expect(await store.nextDispatchAt(), DateTime.utc(2026, 9, 29));
      expect((await store.claimMutation())!.mutation.opId, uid(800));
      expect(await store.nextDispatchAt(), isNull);

      // Releasing the fixture's hold restores the existing retry policy.
      // No budget is reset and the younger alias mutations remain behind it.
      await releaseHolds(head);
      final released = (await store.retryStatus(head))!;
      expect(released.mappingEligible, isTrue);
      expect(released.canRetryManually, isTrue);
      expect(released.nextAttemptAt, status.nextAttemptAt);
      expect(await store.nextAutomaticRetryAt(), status.nextAttemptAt);
      expect(await store.retryMutation(head, expectedAttempt: 1), isTrue);
      final replay = (await store.claimMutation())!;
      expect(replay.mutation.opId, head);
      expect(replay.attempt, 2);
      expect(replay.body, frozen.body);
      expect(replay.hash, frozen.hash);
      expect((await store.retryStatus(head))!.automaticRetriesClaimed, 0);
    });
  }

  test('direct replacement inherits the original logical position', () async {
    await seedDirectSupersession(release: true);

    final before = await tables();
    final snapshot = await store.dispatchSnapshot();
    final original = snapshot.pending.singleWhere((m) => m.opId == uid(701));
    final younger = snapshot.pending.singleWhere((m) => m.opId == uid(702));
    final replacement = snapshot.pending.singleWhere((m) => m.opId == uid(703));

    expect(original.localOrder, lessThan(younger.localOrder));
    expect(younger.localOrder, lessThan(replacement.localOrder));
    expect(snapshot.mapping.orderOf(replacement), original.localOrder);

    final plan = const DependencyPlanner().plan(snapshot);
    expect(plan.ready.map((m) => m.opId), [uid(703)]);
    expect(plan.waiting[uid(701)]!.reason, DispatchWaitReason.superseded);
    expect(plan.waiting[uid(702)]!.reason, DispatchWaitReason.earlierMutation);
    expect(await store.nextDispatchAt(), DateTime.utc(2026, 9, 29));
    expect(await tables(), before);

    final request = (await store.claimMutation())!;
    expect(request.mutation.opId, uid(703));
    expect(request.mutation.localOrder, replacement.localOrder);

    expect(
      await store.deferMutation(request, 'RETRY', 'NETWORK_UNAVAILABLE'),
      isTrue,
    );
    final due = (await store.retryStatus(uid(703)))!.nextAttemptAt;
    expect(due, isNotNull);
    expect(await store.nextAutomaticRetryAt(), due);
    expect(await store.nextDispatchAt(), due);
    expect(await store.claimMutation(), isNull);

    final after = await tables();
    for (final table in [
      'song_aliases',
      'mutation_supersessions',
      'mutation_mapping_holds',
      'canonical_edit_intents',
    ]) {
      expect(after[table], before[table], reason: table);
    }
    for (final opId in [uid(701), uid(702)]) {
      expect(
        rows(after, 'local_mutations').singleWhere((r) => r['op_id'] == opId),
        rows(before, 'local_mutations').singleWhere((r) => r['op_id'] == opId),
      );
    }
  });

  test(
    'an original active hold cannot be bypassed by its replacement',
    () async {
      await seedDirectSupersession(release: false);
      final before = await tables();

      expect(await store.claimMutation(), isNull);
      expect(await store.nextDispatchAt(), isNull);
      expect(await store.nextAutomaticRetryAt(), isNull);
      expect((await store.retryStatus(uid(703)))!.mappingEligible, isFalse);
      expect(await tables(), before);

      await saveUnrelatedTag();
      expect((await store.claimMutation())!.mutation.opId, uid(800));

      await releaseHolds(uid(701));
      expect((await store.claimMutation())!.mutation.opId, uid(703));
    },
  );

  test(
    'supersession chain quarantines its group without stopping a tag',
    () async {
      await seedDirectSupersession(release: true);
      await saveSongPatch(canonical, uid(704), 5);
      await addSupersession(uid(703), uid(704));

      final before = await tables();
      final snapshot = await store.dispatchSnapshot();
      for (final opId in [uid(701), uid(702), uid(703), uid(704)]) {
        expect(snapshot.mapping.allows(opId), isFalse, reason: opId);
      }
      expect(const DependencyPlanner().plan(snapshot).ready, isEmpty);
      expect(await store.claimMutation(), isNull);
      expect(await store.nextDispatchAt(), isNull);
      expect(await store.nextAutomaticRetryAt(), isNull);
      expect(await tables(), before);

      await saveUnrelatedTag();
      expect((await store.claimMutation())!.mutation.opId, uid(800));
    },
  );

  test('source references remain blocked after hold release', () async {
    final request = await seed();
    await relatedEdits();
    expect(await store.applyCanonicalSongReceipt(request, receipt()), isTrue);
    await releaseHolds(uid(230));

    // This PATCH omits song_id, but its frozen base still references source.
    // A release alone does not authorize rewriting or replaying that request.
    final before = await tables();
    final status = (await store.retryStatus(uid(230)))!;
    expect(status.mappingEligible, isFalse);
    expect(status.canRetryManually, isFalse);
    expect(await store.retryMutation(uid(230), expectedAttempt: 2), isFalse);
    final plan = const DependencyPlanner().plan(await store.dispatchSnapshot());
    expect(plan.waiting[uid(230)]!.reason, DispatchWaitReason.mappingBlocked);
    expect(await tables(), before);
  });

  test(
    'alias chain is quarantined without selecting a terminal route',
    () async {
      final request = await seed();
      expect(await store.applyCanonicalSongReceipt(request, receipt()), isTrue);

      final terminal = uid(12);
      await insertCopy(
        entity: LocalEntity.song,
        id: terminal,
        revision: 1,
        server: song(terminal, revision: 1),
        local: song(terminal, revision: 1),
      );

      final db = await raw();
      try {
        await db.customStatement(
          '''
          INSERT INTO local_mutations(
            op_id,user_id,entity_type,entity_id,operation,base_revision,
            payload,request_hash,queue_state,created_at,updated_at
          ) VALUES(?,?,'SONG',?,'CREATE',0,?,?,'ACKED',1,1)
        ''',
          [
            uid(750),
            owner,
            canonical,
            canonicalJson({
              'id': canonical,
              'source_type': 'TJ',
              'source_token': 'fixture',
            }),
            'a' * 64,
          ],
        );
        await db.customStatement(
          '''
          INSERT INTO song_aliases(
            source_song_id,canonical_song_id,user_id,mapping_op_id,
            receipt_status,receipt_body,created_at
          ) VALUES(?,?,?,?,200,?,1)
        ''',
          [
            canonical,
            terminal,
            owner,
            uid(750),
            jsonEncode({
              'created': false,
              'canonical_song_id': terminal,
              'song': song(terminal, revision: 1),
            }),
          ],
        );
      } finally {
        await db.close();
      }

      await saveSongPatch(terminal, uid(751), 1);
      final before = await tables();
      expect((await store.retryStatus(uid(751)))!.mappingEligible, isFalse);
      expect(await store.claimMutation(), isNull);
      expect(await store.nextDispatchAt(), isNull);
      expect(await tables(), before);

      await saveUnrelatedTag();
      expect((await store.claimMutation())!.mutation.opId, uid(800));
    },
  );

  test('attempted original cannot be replaced or reset', () async {
    final mapping = await seed();
    await saveSongPatch(canonical, uid(780), 5);
    final sent = (await store.claimMutation())!;
    expect(sent.mutation.opId, uid(780));
    expect(
      await store.deferMutation(sent, 'RETRY', 'NETWORK_UNAVAILABLE'),
      isTrue,
    );
    expect(await store.applyCanonicalSongReceipt(mapping, receipt()), isTrue);
    await releaseHolds(uid(780));
    await saveSongPatch(canonical, uid(781), 5);
    await addSupersession(uid(780), uid(781));
    final before = await tables();
    expect(await store.claimMutation(), isNull);
    expect(await store.retryMutation(uid(780), expectedAttempt: 1), isFalse);
    expect(await store.nextDispatchAt(), isNull);
    expect((await store.retryStatus(uid(780)))!.attemptCount, 1);
    expect(await tables(), before);
    await saveUnrelatedTag();
    expect((await store.claimMutation())!.mutation.opId, uid(800));
  });

  test('cross target replacement quarantines both targets only', () async {
    final mapping = await seed();
    expect(await store.applyCanonicalSongReceipt(mapping, receipt()), isTrue);
    await saveSongPatch(canonical, uid(790), 5);
    final other = uid(99);
    await insertCopy(
      entity: LocalEntity.song,
      id: other,
      revision: 1,
      server: song(other, revision: 1),
      local: song(other, revision: 1),
    );
    await saveSongPatch(other, uid(791), 1);
    await addSupersession(uid(790), uid(791));
    final before = await tables();
    expect((await store.retryStatus(uid(790)))!.mappingEligible, isFalse);
    expect((await store.retryStatus(uid(791)))!.mappingEligible, isFalse);
    expect(await store.claimMutation(), isNull);
    expect(await store.nextDispatchAt(), isNull);
    expect(await tables(), before);
    await saveUnrelatedTag();
    expect((await store.claimMutation())!.mutation.opId, uid(800));
  });

  test(
    'fan in aliases share order without quarantining direct canonical',
    () async {
      final mapping = await seed();
      expect(await store.applyCanonicalSongReceipt(mapping, receipt()), isTrue);
      final second = uid(13);
      await insertCopy(
        entity: LocalEntity.song,
        id: second,
        revision: 0,
        server: null,
        local: song(second, revision: 0),
      );
      final db = await raw();
      try {
        await db.customStatement(
          '''INSERT INTO local_mutations(
        op_id,user_id,entity_type,entity_id,operation,base_revision,payload,
        request_hash,queue_state,created_at,updated_at)
        VALUES(?,?,'SONG',?,'CREATE',0,?,?,'ACKED',1,1)''',
          [
            uid(795),
            owner,
            second,
            canonicalJson({
              'id': second,
              'source_type': 'TJ',
              'source_token': 'fixture',
            }),
            'a' * 64,
          ],
        );
        await db.customStatement(
          '''INSERT INTO song_aliases(
        source_song_id,canonical_song_id,user_id,mapping_op_id,receipt_status,receipt_body,created_at)
        VALUES(?,?,?,?,200,?,1)''',
          [
            second,
            canonical,
            owner,
            uid(795),
            jsonEncode({
              'created': false,
              'canonical_song_id': canonical,
              'song': song(canonical, revision: 5),
            }),
          ],
        );
      } finally {
        await db.close();
      }
      await saveSongPatch(second, uid(796), 0);
      await saveSongPatch(canonical, uid(797), 5);
      final before = await tables();
      expect((await store.retryStatus(uid(797)))!.mappingEligible, isTrue);
      final plan = const DependencyPlanner().plan(
        await store.dispatchSnapshot(),
      );
      expect(plan.waiting[uid(796)]!.reason, DispatchWaitReason.mappingBlocked);
      expect(
        plan.waiting[uid(797)]!.reason,
        DispatchWaitReason.earlierMutation,
      );
      expect(await store.claimMutation(), isNull);
      expect(await tables(), before);
      await saveUnrelatedTag();
      expect((await store.claimMutation())!.mutation.opId, uid(800));
    },
  );

  // apps/mobile/test/canonical_song_store_test.dart
  // 기존 main() 내부에 추가. 기존 SQLite fixture와 helper를 사용한다.
  // dispatcher 연결, hold 해제, 스키마 변경은 없다.

  for (final variant in [
    (mapped: true, revision: 3, tombstone: false),
    (mapped: true, revision: 7, tombstone: false),
    (mapped: true, revision: 3, tombstone: true),
    (mapped: false, revision: 3, tombstone: false),
  ]) {
    test('늦은 ACK의 로컬 매핑·서버 기준 보호: $variant', () async {
      final recordingId = uid(840);
      final patchOp = uid(841);
      final downstreamOp = uid(842);
      final baseline = <String, Object?>{
        'id': recordingId,
        'song_id': source,
        'revision': 3,
        'note': 'server',
      };
      final draft = <String, Object?>{
        ...baseline,
        'note': 'private',
        'unknown_local_field': {'keep': true},
      };

      await insertCopy(
        entity: LocalEntity.recording,
        id: recordingId,
        revision: 3,
        server: baseline,
        local: draft,
      );
      await store.saveEdit(
        LocalEdit(
          opId: patchOp,
          entity: LocalEntity.recording,
          entityId: recordingId,
          operation: LocalOperation.patch,
          baseRevision: 3,
          draft: draft,
          changes: {'base_revision': 3, 'note': 'private'},
        ),
      );

      // 소스 CREATE를 넣기 전에 실제 claim으로 PATCH를 전송 중으로 만든다.
      // queue_state나 frozen wire를 SQL로 조작하지 않는다.
      final request = (await store.claimMutation())!;
      expect(request.mutation.opId, patchOp);
      expect(request.mutation.entity, LocalEntity.recording);
      expect(request.mutation.operation, LocalOperation.patch);
      expect(request.attempt, 1);

      final inFlight = (await store.pendingMutations()).single;
      expect(inFlight.state, 'SENDING');
      expect(inFlight.attemptCount, request.attempt);

      if (variant.mapped) {
        final mappingRequest = await seed();
        expect(
          await store.applyCanonicalSongReceipt(mappingRequest, receipt()),
          isTrue,
        );
      }

      if (variant.revision > 3 || variant.tombstone) {
        // ACK 전에 도착한 서버 상태만 모사한다. 로컬 projection은 유지한다.
        // tombstone 사례는 revision 3으로, revision 비교와 독립적으로 검사한다.
        final db = await raw();
        try {
          await db.customStatement(
            '''
            UPDATE metadata_copies
            SET server_revision=?,server_payload=?,tombstone=?,updated_at=2
            WHERE entity_type='RECORDING' AND entity_id=?
          ''',
            [
              variant.revision,
              canonicalJson({
                ...baseline,
                'revision': variant.revision,
                'note': variant.tombstone
                    ? 'deleted on server'
                    : 'newer server',
              }),
              variant.tombstone ? 1 : 0,
              recordingId,
            ],
          );
        } finally {
          await db.close();
        }
      }

      final before = await tables();
      final beforeCopy = rows(before, 'metadata_copies').singleWhere(
        (row) =>
            row['entity_type'] == 'RECORDING' &&
            row['entity_id'] == recordingId,
      );
      final beforeMutation = rows(
        before,
        'local_mutations',
      ).singleWhere((row) => row['op_id'] == patchOp);
      final beforeControl = rows(
        before,
        'mutation_retry_controls',
      ).singleWhere((row) => row['op_id'] == patchOp);
      final holds = rows(
        before,
        'mutation_mapping_holds',
      ).where((row) => row['op_id'] == patchOp).toList();

      expect(beforeMutation['queue_state'], 'SENDING');
      expect(jsonDecode(beforeCopy['local_payload'] as String), {
        ...draft,
        'song_id': variant.mapped ? canonical : source,
      });
      if (variant.mapped) {
        expect(holds, hasLength(1));
        expect(holds.single['disposition'], 'BLOCK');
        expect(holds.single['released_at'], isNull);
      } else {
        expect(holds, isEmpty);
      }

      // ACK 전 후속 mutation이 없어야 기존 later-count 분기가 결함을 가리지 않는다.
      expect(
        rows(before, 'local_mutations')
            .where(
              (row) =>
                  row['entity_type'] == 'RECORDING' &&
                  row['entity_id'] == recordingId &&
                  row['queue_state'] != 'ACKED',
            )
            .map((row) => row['op_id']),
        [patchOp],
      );

      final ack = <String, Object?>{
        ...baseline,
        'revision': 4,
        'note': 'private',
      };
      final ackJson = canonicalJson(ack);

      // 활성 hold가 있어도 attempt·frozen body 검증은 그대로 적용해야 한다.
      for (final invalid in [
        MutationRequest(
          mutation: request.mutation,
          method: request.method,
          path: request.path,
          body: request.body,
          attempt: request.attempt + 1,
        ),
        MutationRequest(
          mutation: request.mutation,
          method: request.method,
          path: request.path,
          body: '${request.body} ',
          attempt: request.attempt,
        ),
      ]) {
        expect(await store.acknowledgeMutation(invalid, ack), isFalse);
        expect(await tables(), before);
      }

      expect(await store.acknowledgeMutation(request, ack), isTrue);
      final after = await tables();
      final afterCopy = rows(after, 'metadata_copies').singleWhere(
        (row) =>
            row['entity_type'] == 'RECORDING' &&
            row['entity_id'] == recordingId,
      );

      if (variant.tombstone || variant.revision > 4) {
        // 최신 서버 상태 또는 tombstone은 행 전체를 유지한다.
        expect(afterCopy, beforeCopy);
      } else {
        // hold가 있어도 서버 snapshot은 저장한다.
        // hold가 없고 후속 수정도 없으면 기존처럼 로컬까지 ACK로 교체한다.
        expect(afterCopy, {
          ...beforeCopy,
          'server_revision': 4,
          'server_payload': ackJson,
          'local_payload': variant.mapped
              ? beforeCopy['local_payload']
              : ackJson,
          'updated_at': afterCopy['updated_at'],
        });
      }

      final afterMutation = rows(
        after,
        'local_mutations',
      ).singleWhere((row) => row['op_id'] == patchOp);
      expect(afterMutation, {
        ...beforeMutation,
        'queue_state': 'ACKED',
        'server_response': ackJson,
        'updated_at': afterMutation['updated_at'],
      });
      expect(
        rows(
          after,
          'mutation_retry_controls',
        ).singleWhere((row) => row['op_id'] == patchOp),
        {...beforeControl, 'retry_mode': 'BLOCKED'},
      );

      for (final table in [
        'mutation_mapping_holds',
        'mutation_wire_requests',
        'song_aliases',
        'canonical_edit_intents',
        'mutation_supersessions',
      ]) {
        expect(after[table], before[table], reason: table);
      }

      expect(await store.acknowledgeMutation(request, ack), isFalse);
      expect(await tables(), after);

      if (variant.mapped && variant.revision == 3 && !variant.tombstone) {
        // 핵심 회귀 사례에서 ACK를 먼저 끝낸 뒤 후속 작업을 만든다.
        final mappedDraft = jsonDecode(
          afterCopy['local_payload'] as String,
        ) as Map<String, dynamic>;
        expect(mappedDraft['song_id'], canonical);

        await store.saveEdit(
          LocalEdit(
            opId: downstreamOp,
            entity: LocalEntity.recording,
            entityId: recordingId,
            operation: LocalOperation.patch,
            baseRevision: 4,
            draft: {...mappedDraft, 'revision': 4, 'note': 'next edit'},
            changes: {'base_revision': 4, 'note': 'next edit'},
          ),
        );

        final beforeDispatch = await tables();
        final plan = const DependencyPlanner().plan(
          await store.dispatchSnapshot(),
        );
        expect(plan.ready, isEmpty);
        expect(
          plan.waiting[downstreamOp]!.reason,
          DispatchWaitReason.mappingBlocked,
        );
        expect(
          (await store.retryStatus(downstreamOp))!.mappingEligible,
          isFalse,
        );
        expect(await store.nextAutomaticRetryAt(), isNull);
        expect(await store.nextDispatchAt(), isNull);
        expect(await store.claimMutation(), isNull);
        expect(await tables(), beforeDispatch);
        expect(
          beforeDispatch['mutation_mapping_holds'],
          before['mutation_mapping_holds'],
        );
      }
    });
  }

  final failures = <String, String>{
    'canonical insert': '''
      CREATE TRIGGER injected BEFORE INSERT ON metadata_copies
      WHEN NEW.entity_type='SONG'
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'alias': '''
      CREATE TRIGGER injected BEFORE INSERT ON song_aliases
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'intent': '''
      CREATE TRIGGER injected BEFORE INSERT ON canonical_edit_intents
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'hold': '''
      CREATE TRIGGER injected BEFORE INSERT ON mutation_mapping_holds
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'reference rewrite': '''
      CREATE TRIGGER injected BEFORE UPDATE ON metadata_copies
      WHEN NEW.entity_type='RECORDING'
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'ACK': '''
      CREATE TRIGGER injected BEFORE UPDATE ON local_mutations
      WHEN NEW.queue_state='ACKED'
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
    'retry finish': '''
      CREATE TRIGGER injected BEFORE UPDATE ON mutation_retry_controls
      WHEN NEW.retry_mode='BLOCKED'
      BEGIN SELECT RAISE(ABORT,'injected'); END
    ''',
  };

  for (final failure in failures.entries) {
    test('entire transaction rolls back on ${failure.key}', () async {
      final request = await seed(canonicalRevision: null);

      // Ensure the hold and reference-update stages are reached.
      await store.saveEdit(
        LocalEdit(
          opId: uid(600),
          entity: LocalEntity.recording,
          entityId: uid(60),
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: {'id': uid(60), 'song_id': source, 'note': 'private'},
          changes: {
            'id': uid(60),
            'metadata_state': 'DRAFT',
            'song_id': source,
          },
        ),
      );

      final db = await raw();
      try {
        await db.customStatement(failure.value);
      } finally {
        await db.close();
      }
      final before = await tables();

      await expectLater(
        store.applyCanonicalSongReceipt(request, receipt()),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'remote SQL cause',
            allOf(contains('SqliteException(1811)'), contains('injected')),
          ),
        ),
      );
      expect(await tables(), before);
    });
  }

  test(
    'account invalidation during transaction causes full rollback',
    () async {
      final request = await seed(canonicalRevision: null);
      final before = await tables();
      final db = await raw();
      Future<void>? closing;

      try {
        // Synchronously invalidates the generation when the mapper reads time.
        // logout's serialized close runs after the current action finishes.
        onClock = () {
          closing = manager.logout();
        };

        await expectLater(
          store.applyCanonicalSongReceipt(request, receipt()),
          throwsStateError,
        );
        await closing!;

        // Read through the low-level connection so opening recovery does not
        // change SENDING to RETRY before the rollback assertion.
        final after = <String, Object?>{};
        for (final table in before.keys) {
          final query = table == 'local_mutations'
              ? 'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid'
              : 'SELECT * FROM $table';
          after[table] = (await db.customSelect(query).get())
              .map((row) => row.data)
              .toList();
        }
        expect(after, before);
      } finally {
        await db.close();
      }
    },
  );
}
