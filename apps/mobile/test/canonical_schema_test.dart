import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

String uid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
const canonicalTables = [
  'song_aliases',
  'mutation_supersessions',
  'canonical_edit_intents',
  'mutation_mapping_holds',
];
const added = [...canonicalTables, 'mutation_conflict_resolutions', 'pending_edit_resolutions'];

Future<void> assertOrderProtected(AccountDatabase db) async {
  final before =
      (await db
              .customSelect(
                'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
              )
              .get())
          .map((r) => r.data)
          .toList();
  for (final alias in ['rowid', 'oid', '_rowid_']) {
    for (final update in ['UPDATE', 'UPDATE OR REPLACE']) {
      await expectLater(
        db.customStatement('$update local_mutations SET $alias=1000000'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    await expectLater(
      db.customStatement(
        'INSERT OR REPLACE INTO local_mutations($alias,op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) SELECT $alias,op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at FROM local_mutations',
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  }
  // A fresh op_id isolates rowid collision and nonpositive-order guards.
  for (final order in [0, -1, -2, ...before.map((r) => r['local_order'])]) {
    await expectLater(
      db.customStatement(
        'INSERT OR REPLACE INTO local_mutations(rowid,op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) SELECT ?,?,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at FROM local_mutations LIMIT 1',
        [order, uid(9999)],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  }
  await expectLater(
    db.customStatement('DELETE FROM local_mutations'),
    throwsA(isA<sqlite.SqliteException>()),
  );
  await db.customStatement(
    'UPDATE local_mutations SET rowid=rowid,updated_at=updated_at',
  );
  expect(
    (await db
            .customSelect(
              'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
            )
            .get())
        .map((r) => r.data)
        .toList(),
    before,
  );
}

void main() {
  test(
    'current Drift source and snapshot use portable SQL line endings',
    () async {
      // Git eol attributes do not normalize a file rewritten by a local script.
      // Detect that mismatch locally before Linux regeneration rejects the snapshot.
      final source = await File('lib/core/database/local_schema.drift')
          .readAsString();
      expect(source, isNot(contains('\r')));
      final db = AccountDatabase(
        NativeDatabase.memory(),
        userId: uid(1),
        environment: AppEnvironment.dev,
      );
      try {
        final schema = jsonDecode(
          await File(
            'drift_schemas/account/drift_schema_v${db.schemaVersion}.json',
          ).readAsString(),
        ) as Map;
        for (final entity in schema['entities'] as List) {
          final sql = (entity['data'] as Map)['sql'];
          if (sql is String) expect(sql, isNot(contains('\r')));
        }
      } finally {
        await db.close();
      }
    },
  );
  test('recovery export includes every new preservation table', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sr-canonical-export-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
    );
    try {
      final store = await manager.openAccount(uid(1));
      final exported =
          jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
      final tables = exported['tables'] as Map<String, dynamic>;
      for (final name in added) {
        expect(tables[name], isEmpty);
      }
    } finally {
      await manager.logout();
      await directory.delete(recursive: true);
    }
  });
  for (final version in [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
    test('v$version to v11 preserves old rows, wire, budget, cursor and synthetic file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sr-canonical-migration-',
      );
      final file = File('${directory.path}/account.sqlite');
      final audio = File('${directory.path}/audio/${uid(4)}.m4a');
      await audio.parent.create();
      final bytes = [7, 8, 9];
      await audio.writeAsBytes(bytes);
      final owner = uid(1),
          entity = uid(2),
          operation = uid(3),
          recording = uid(4);
      final old = sqlite.sqlite3.open(file.path);
      old.execute(
        await File('test/fixtures/local_schema_v$version.sql').readAsString(),
      );
      old.execute('PRAGMA user_version=$version');
      old.execute("INSERT INTO local_account VALUES(1,?,'dev',1)", [owner]);
      old.execute(
        'INSERT INTO sync_cursors(singleton,user_id,last_change_seq,baseline_complete,updated_at) VALUES(1,?,17,1,1)',
        [owner],
      );
      final body = jsonEncode({'id': entity, 'name': 'synthetic pending'});
      old.execute(
        "INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at) VALUES(?,'TAG',?,?,1)",
        [owner, entity, body],
      );
      final state = version == 1
          ? 'PENDING'
          : version == 2
          ? 'SENDING'
          : 'RETRY';
      final attempt = version == 1 ? 0 : 2;
      final due = version == 3
          ? DateTime.utc(2030).millisecondsSinceEpoch
          : null;
      old.execute(
        "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,queue_state,attempt_count,next_attempt_at,created_at,updated_at) VALUES(?,?,'TAG',?,'CREATE',0,?,?,?,?,?,1,1)",
        [operation, owner, entity, body, 'a' * 64, state, attempt, due],
      );
      if (version >= 2) {
        old.execute(
          "INSERT INTO mutation_wire_requests VALUES(?,'metadata-v1','POST','/v1/tags',?,?)",
          [operation, body, 'b' * 64],
        );
      }
      if (version >= 3) {
        old.execute(
          "INSERT INTO mutation_retry_controls VALUES(?,1,'AUTO','AUTO')",
          [operation],
        );
      }
      old.execute(
        "INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at) VALUES(?,?,?, ?,3,'SAVED',1,1)",
        [
          recording,
          owner,
          'audio/$recording.m4a',
          sha256.convert(bytes).toString(),
        ],
      );
      old.execute(
        "INSERT INTO recording_journals(recording_id,user_id,operation_id,pending_path,final_path,phase,recovery_payload,updated_at) VALUES(?,?,?,?,?,'COMMITTED',?,1)",
        [
          recording,
          owner,
          uid(5),
          'pending/$recording.m4a.part',
          'audio/$recording.m4a',
          jsonEncode({'song_id': uid(6), 'note': 'synthetic draft'}),
        ],
      );
      if (version >= 5) {
        // Exercise nonempty retained baseline tables as well as queue/file rows.
        final token = uid(30);
        old.execute(
          'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,17,999999,1)',
          [
            token,
            owner,
            jsonEncode({'snapshot_token': token, 'snapshot_cursor': 17}),
          ],
        );
        old.execute(
          "INSERT INTO snapshot_download_rows VALUES(?,?,'TAG',1,?,?)",
          [
            token,
            owner,
            entity,
            jsonEncode({
              'id': entity,
              'user_id': owner,
              'name': 'preserved baseline',
            }),
          ],
        );
        old.execute(
          "INSERT INTO snapshot_download_progress VALUES(?,'TAG',1,NULL,1)",
          [token],
        );
        old.execute("UPDATE snapshot_downloads SET state='VERIFIED'");
        old.execute("UPDATE snapshot_downloads SET state='APPLIED'");
        old.execute('INSERT INTO snapshot_baseline VALUES(1,?,?)', [
          token,
          owner,
        ]);
      }
      if (version >= 7) {
        // Nonempty v7 history must survive the trigger-only v8 migration.
        final recorded = jsonEncode({'id': recording, 'revision': 1});
        old.execute(
          "INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,'RECORDING',?,1,?,1)",
          [owner, recording, recorded],
        );
        for (final index in [0, 1, 2]) {
          old.execute(
            'INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,base_payload,payload,request_hash,queue_state,attempt_count,server_response,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1,1)',
            [
              uid(80 + index),
              owner,
              'RECORDING',
              recording,
              index == 0 ? 'CREATE' : 'PATCH',
              index == 2 ? 1 : 0,
              index == 2 ? recorded : null,
              jsonEncode(
                index == 0
                    ? {'id': recording}
                    : {'base_revision': index == 2 ? 1 : 0, 'note': 'retained'},
              ),
              'c' * 64,
              index == 0 ? 'ACKED' : 'PENDING',
              index == 0 ? 1 : 0,
              index == 0 ? recorded : null,
            ],
          );
        }
        old.execute(
          'INSERT INTO recording_followups SELECT ?,?,?,?,rowid,1 FROM local_mutations WHERE op_id=?',
          [uid(81), uid(82), uid(80), owner, uid(81)],
        );
      }
      if (version == 3) {
        // Preserve an unusual legacy negative rowid; new v4 inserts reject it.
        old.execute(
          'INSERT INTO local_mutations(rowid,op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) SELECT -1,?,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at FROM local_mutations LIMIT 1',
          [uid(20)],
        );
      }
      final before = <String, List<Map<String, Object?>>>{};
      for (final table
          in old
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((row) => row['name'] as String)) {
        before[table] = old
            .select('SELECT * FROM $table')
            .map((row) => Map<String, Object?>.from(row))
            .toList();
      }
      final oldOrder = old
          .select(
            'SELECT rowid AS local_order,op_id FROM local_mutations ORDER BY rowid',
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      old.close();
      final db = AccountDatabase(
        NativeDatabase(file),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      try {
        await db.verifyReady();
        expect(
          (await db
                  .customSelect(
                    'SELECT rowid AS local_order,op_id FROM local_mutations ORDER BY rowid',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
          oldOrder,
        );
        await assertOrderProtected(db);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          11,
        );
        for (final entry in before.entries) {
          expect(
            (await db.customSelect('SELECT * FROM ${entry.key}').get())
                .map((row) => row.data)
                .toList(),
            entry.value,
            reason: entry.key,
          );
        }
        for (final table in added) {
          expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
        }
        final indexes =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type='index'",
                    )
                    .get())
                .map((row) => row.read<String>('name'));
        expect(
          indexes,
          containsAll([
            'song_alias_destination',
            'canonical_intent_target',
            'mutation_mapping_active_holds',
          ]),
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(await audio.readAsBytes(), bytes);
        await db.customStatement(
          'INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) SELECT ?,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at FROM local_mutations LIMIT 1',
          [uid(9998)],
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT rowid AS local_order FROM local_mutations WHERE op_id='${uid(9998)}'",
                  )
                  .getSingle())
              .read<int>('local_order'),
          greaterThan(0),
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true); // Only this synthetic fixture.
      }
    });
  }

  test('new schema keeps canonical receipt and alias evidence immutable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sr-canonical-evidence-',
    );
    final paths = await AccountPaths.create(
      directory,
      uid(1),
      AppEnvironment.dev,
    );
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: uid(1),
      environment: AppEnvironment.dev,
    );
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    await db.verifyReady();
    for (final id in [uid(2), uid(3)]) {
      await db.customStatement(
        "INSERT INTO metadata_copies(user_id,entity_type,entity_id,updated_at) VALUES(?,'SONG',?,0)",
        [uid(1), id],
      );
    }
    for (final pair in [
      [uid(4), uid(2)],
      [uid(5), uid(3)],
    ]) {
      await db.customStatement(
        "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) VALUES(?,?,'SONG',?,'CREATE',0,?,?,0,0)",
        [
          pair[0],
          uid(1),
          pair[1],
          jsonEncode({
            'id': pair[1],
            'source_type': 'TJ',
            'source_token': 'synthetic',
          }),
          'a' * 64,
        ],
      );
    }
    String receipt(String destination, Object? created) => jsonEncode({
      'created': created,
      'canonical_song_id': destination,
      'song': {'id': destination, 'revision': 1, 'lifecycle_state': 'ACTIVE'},
    });
    const insert =
        'INSERT INTO song_aliases(source_song_id,canonical_song_id,user_id,mapping_op_id,receipt_status,receipt_body,created_at) VALUES(?,?,?,?,200,?,0)';
    for (final created in [true, null, 'false']) {
      await expectLater(
        db.customStatement(insert, [
          uid(2),
          uid(3),
          uid(1),
          uid(4),
          receipt(uid(3), created),
        ]),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    await db.customStatement(insert, [
      uid(2),
      uid(3),
      uid(1),
      uid(4),
      receipt(uid(3), false),
    ]);
    await expectLater(
      db.customStatement(insert, [
        uid(3),
        uid(2),
        uid(1),
        uid(5),
        receipt(uid(2), false),
      ]),
      throwsA(isA<sqlite.SqliteException>()),
    );
    for (final sql in [
      'UPDATE song_aliases SET created_at=2',
      'DELETE FROM song_aliases',
    ]) {
      await expectLater(
        db.customStatement(sql),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(
      (await db.customSelect('SELECT * FROM song_aliases').get()).length,
      1,
    );

    await assertOrderProtected(db);
    await expectLater(
      db.customStatement(
        'UPDATE OR REPLACE local_mutations SET rowid=2 WHERE rowid=1',
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO mutation_supersessions VALUES(?,?,?,?,?,?,0)',
        [uid(5), uid(4), uid(2), uid(1), uid(5), 2],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    // Append-only chains preserve their original order; prepending cannot rewrite it.
    for (final operation in [uid(8), uid(9)]) {
      await db.customStatement(
        "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) VALUES(?,?,'SONG',?,'CREATE',0,?,?,0,0)",
        [operation, uid(1), uid(3), '{}', 'a' * 64],
      );
    }
    await db.customStatement(
      'INSERT INTO mutation_supersessions VALUES(?,?,?,?,?,?,0)',
      [uid(5), uid(8), uid(2), uid(1), uid(5), 2],
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO mutation_supersessions VALUES(?,?,?,?,?,?,0)',
        [uid(4), uid(5), uid(2), uid(1), uid(4), 1],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      'INSERT INTO mutation_supersessions VALUES(?,?,?,?,?,?,0)',
      [uid(8), uid(9), uid(2), uid(1), uid(5), 2],
    );
    for (final sql in [
      'UPDATE mutation_supersessions SET logical_order=2',
      'DELETE FROM mutation_supersessions',
      "UPDATE local_mutations SET attempt_count=1 WHERE op_id='${uid(5)}'",
    ]) {
      await expectLater(
        db.customStatement(sql),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    // Preserve both private drafts as opaque evidence. Resolving it is one-way.
    await db.customStatement(
      "INSERT INTO canonical_edit_intents(intent_id,user_id,mapping_source_id,intent_key,kind,entity_type,entity_id,origin_op_id,evidence_json,created_at) VALUES(?,?,?,'values','SONG_VALUES','SONG',?,?,?,0)",
      [
        uid(6),
        uid(1),
        uid(2),
        uid(2),
        uid(4),
        jsonEncode({'version': 1, 'source': 'synthetic', 'canonical': 'other'}),
      ],
    );
    await expectLater(
      db.customStatement(
        "UPDATE canonical_edit_intents SET evidence_json='{}'",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      "UPDATE canonical_edit_intents SET state='RESOLVED',resolution_json='{}',resolved_at=1",
    );
    await expectLater(
      db.customStatement('UPDATE canonical_edit_intents SET resolved_at=2'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      "INSERT INTO mutation_mapping_holds(op_id,mapping_source_id,user_id,reason,disposition,intent_id,created_at) VALUES(?,?,?,'TEST_BLOCK','BLOCK',?,0)",
      [uid(4), uid(2), uid(1), uid(6)],
    );
    await expectLater(
      db.customStatement(
        "UPDATE mutation_mapping_holds SET disposition='REPLAY_ORIGINAL'",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      "UPDATE mutation_mapping_holds SET released_at=1,release_evidence='{}'",
    );
    await expectLater(
      db.customStatement('UPDATE mutation_mapping_holds SET released_at=2'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    for (final table in ['canonical_edit_intents', 'mutation_mapping_holds']) {
      await expectLater(
        db.customStatement('DELETE FROM $table'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    // Only these tables have rows in this canonical mapping fixture. Resolution
    // replacement protection is tested with populated rows in its own tests.
    for (final table in canonicalTables) {
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO $table SELECT * FROM $table',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    // Hidden row identities must not provide a REPLACE escape hatch.
    for (final table in added) {
      for (final column in ['rowid', '_rowid_', 'oid']) {
        await expectLater(
          db.customSelect('SELECT $column FROM $table').get(),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          db.customStatement('UPDATE OR REPLACE $table SET $column=1'),
          throwsA(isA<sqlite.SqliteException>()),
        );
      }
    }
    // Explicit gaps; physical order differs from op_id order.
    for (final pair in [(100, uid(100)), (200, uid(99))]) {
      await db.customStatement(
        '''
    INSERT INTO local_mutations(
      rowid,op_id,user_id,entity_type,entity_id,operation,
      base_revision,payload,request_hash,created_at,updated_at
    ) VALUES(?,?,?,'SONG',?,'CREATE',0,'{}',?,0,0)
    ''',
        [pair.$1, pair.$2, uid(1), uid(3), 'a' * 64],
      );
    }
    await db.customStatement(
      '''
  INSERT INTO mutation_supersessions(
    original_op_id,replacement_op_id,mapping_source_id,
    user_id,order_root_op_id,logical_order,created_at
  ) VALUES(?,?,?,?,?,?,0)
  ''',
      [uid(100), uid(99), uid(2), uid(1), uid(100), 100],
    );
    Future<List<Map<String, Object?>>> mutationRows() async =>
        (await db
                .customSelect(
                  'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
                )
                .get())
            .map((row) => row.data)
            .toList();

    final mutationsBefore = await mutationRows();
    final expected = <String, Object?>{};
    for (final table in added) {
      expected[table] = (await db.customSelect('SELECT * FROM $table').get())
          .map((row) => row.data)
          .toList();
    }
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
    );
    try {
      final store = await manager.openAccount(uid(1));
      final exported =
          jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
      final tables = exported['tables'] as Map<String, dynamic>;
      for (final table in added) {
        expect(tables[table], expected[table]);
      }
      expect(exported['format'], 'song-record-local-recovery');
      expect(exported['version'], 2);
      expect(exported['schema_version'], 11);
      expect(tables['local_mutations'], mutationsBefore);

      final mutations = (tables['local_mutations'] as List)
          .cast<Map<String, dynamic>>();
      expect(mutations.map((row) => row['local_order']).toList(), [
        1,
        2,
        3,
        4,
        100,
        200,
      ]);
      expect(mutations.map((row) => row['op_id']).toList(), [
        uid(4),
        uid(5),
        uid(8),
        uid(9),
        uid(100),
        uid(99),
      ]);

      final byOp = {for (final row in mutations) row['op_id'] as String: row};
      for (final edge in tables['mutation_supersessions'] as List) {
        expect(
          edge['logical_order'],
          byOp[edge['order_root_op_id']]!['local_order'],
        );
      }

      final again =
          jsonDecode(await store.recoveryData()) as Map<String, dynamic>;
      expect(again['tables'], tables); // created_at is intentionally excluded.
      expect(await mutationRows(), mutationsBefore);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally {
      await manager.logout();
    }
  });
}
