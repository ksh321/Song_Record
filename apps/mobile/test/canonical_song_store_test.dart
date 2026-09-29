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
import 'package:song_record/core/sync/mutation_request.dart';

String uid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

const timestamp = '2026-09-29T00:00:00Z';

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
          after[table] = (await db.customSelect('SELECT * FROM $table').get())
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
