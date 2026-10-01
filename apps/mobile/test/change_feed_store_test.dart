import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/change_feed_store.dart';
import 'package:song_record/core/sync/change_feed_response.dart';

import 'change_payload_validation_test.dart' show songChange, recordingWire;

void main() {
  const owner = '11111111-1111-4111-8111-111111111111';
  const token = '22222222-2222-4222-8222-222222222222';
  const id = '33333333-3333-4333-8333-333333333333';
  const other = '44444444-4444-4444-8444-444444444444';
  late AccountDatabase db;
  late ChangeFeedStore store;
  var fenceCalls = 0, failAt = 0;
  setUp(() async {
    db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    fenceCalls = 0;
    failAt = 0;
    store = ChangeFeedStore(
      db,
      clock: () => DateTime.utc(2026, 10, 1),
      requireActive: () {
        if (++fenceCalls == failAt) throw StateError('Account changed');
      },
    );
    final manifest = (jsonDecode(
      File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
    ) as Map)['manifest'];
    await db.customStatement(
      'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,7,1800000,0)',
      [token, owner, jsonEncode(manifest)],
    );
    await db.customStatement("UPDATE snapshot_downloads SET state='VERIFIED'");
    await db.customStatement("UPDATE snapshot_downloads SET state='APPLIED'");
    await db.customStatement('INSERT INTO snapshot_baseline VALUES(1,?,?)', [
      token,
      owner,
    ]);
    await db.customStatement(
      'UPDATE sync_cursors SET last_change_seq=7,baseline_complete=1',
    );
  });
  tearDown(() async {
    await db.close();
  });
  Future<String> replaceBaseline(
    String entity,
    Map<String, Object?> payload, {
    Map<String, List<Map<String, Object?>>> relations = const {},
  }) async {
    final original =
        (await db
                .customSelect('SELECT manifest_json FROM snapshot_downloads')
                .getSingle())
            .read<String>('manifest_json');
    final manifest = jsonDecode(original) as Map<String, dynamic>;
    manifest['snapshot_token'] = other;
    final counts = manifest['entity_counts'] as Map<String, dynamic>;
    counts.updateAll(
      (key, value) => key == entity ? 1 : relations[key]?.length ?? 0,
    );
    await db.customStatement(
      'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,7,1800000,0)',
      [other, owner, jsonEncode(manifest)],
    );
    await db.customStatement(
      'INSERT INTO snapshot_download_rows VALUES(?,?,?,1,?,?)',
      [other, owner, entity, id, jsonEncode(payload)],
    );
    for (final relation in relations.entries) {
      for (var index = 0; index < relation.value.length; index++) {
        await db.customStatement(
          'INSERT INTO snapshot_download_rows VALUES(?,?,?,?,?,?)',
          [
            other,
            owner,
            relation.key,
            index + 1,
            id,
            jsonEncode(relation.value[index]),
          ],
        );
      }
    }
    await db.customStatement(
      "UPDATE snapshot_downloads SET state='VERIFIED' WHERE snapshot_token=?",
      [other],
    );
    await db.customStatement(
      "UPDATE snapshot_downloads SET state='APPLIED' WHERE snapshot_token=?",
      [other],
    );
    await db.customStatement('UPDATE snapshot_baseline SET snapshot_token=?', [
      other,
    ]);
    return other;
  }

  Map<String, Object?> entry(
    int seq,
    String entityId, {
    int revision = 2,
    bool deleted = false,
  }) => {
    'change_seq': seq,
    'entity_type': 'SONG',
    'entity_id': entityId,
    'revision': revision,
    'operation': deleted ? 'DELETE' : 'UPSERT',
    'payload': songChange(entityId, revision),
  };
  ChangeFeedPage page(
    List<Map<String, Object?>> entries, {
    String account = owner,
    int after = 7,
  }) => ChangeFeedPage.decode(
    jsonEncode({
      'after_seq': after,
      'next_seq': after + entries.length,
      'head_seq': after + entries.length,
      'has_more': false,
      'changes': entries,
    }),
    owner: account,
    expectedAfter: after,
  );
  Future<int> cursor() async =>
      (await db
              .customSelect('SELECT last_change_seq FROM sync_cursors')
              .getSingle())
          .read<int>('last_change_seq');
  Future<void> seed({
    int revision = 1,
    bool tombstone = false,
    String? local = 'draft',
  }) => db.customStatement(
    'INSERT INTO metadata_copies VALUES(?,?,?,?,?,?,?,0)',
    [
      owner,
      'SONG',
      id,
      revision,
      jsonEncode({'id': id, 'revision': revision, 'title': 'old'}),
      local == null ? null : jsonEncode({'title': local}),
      tombstone ? 1 : 0,
    ],
  );

  test(
    'whole page updates server state and cursor but preserves local draft',
    () async {
      await seed();
      await store.apply(
        page([entry(8, id), entry(9, other)]),
        snapshotToken: token,
      );
      final row = await db
          .customSelect("SELECT * FROM metadata_copies WHERE entity_id='$id'")
          .getSingle();
      expect(row.read<int>('server_revision'), 2);
      expect(jsonDecode(row.read<String>('local_payload')), {'title': 'draft'});
      expect(await cursor(), 9);
    },
  );
  test('final account fence rolls back every row and cursor', () async {
    failAt = 4; // initial + two rows + pre-commit
    await expectLater(
      store.apply(page([entry(8, id), entry(9, other)]), snapshotToken: token),
      throwsStateError,
    );
    expect(
      await db.customSelect('SELECT * FROM metadata_copies').get(),
      isEmpty,
    );
    expect(await cursor(), 7);
  });
  test('late invalid payload rolls back an earlier valid row', () async {
    final bad = entry(9, other);
    bad['payload'] = {'title': 'partial'};
    await expectLater(
      store.apply(page([entry(8, id), bad]), snapshotToken: token),
      throwsFormatException,
    );
    expect(
      await db.customSelect('SELECT * FROM metadata_copies').get(),
      isEmpty,
    );
    expect(await cursor(), 7);
  });
  test(
    'wrong owner, replaced baseline and duplicate page cannot advance cursor',
    () async {
      await expectLater(
        store.apply(page([entry(8, id)], account: other), snapshotToken: token),
        throwsStateError,
      );
      await expectLater(
        store.apply(page([entry(8, id)]), snapshotToken: other),
        throwsStateError,
      );
      await store.apply(page([entry(8, id)]), snapshotToken: token);
      await expectLater(
        store.apply(page([entry(8, id)]), snapshotToken: token),
        throwsStateError,
      );
      expect(await cursor(), 8);
    },
  );
  test(
    'newer acknowledged revision and permanent tombstones cannot rewind',
    () async {
      await seed(revision: 5, local: null);
      await store.apply(page([entry(8, id)]), snapshotToken: token);
      expect(
        (await db
                .customSelect('SELECT server_revision FROM metadata_copies')
                .getSingle())
            .read<int>('server_revision'),
        5,
      );
      await db.customStatement('UPDATE metadata_copies SET tombstone=1');
      await store.apply(
        page([entry(9, id, revision: 6)], after: 8),
        snapshotToken: token,
      );
      final row = await db
          .customSelect('SELECT * FROM metadata_copies')
          .getSingle();
      expect(row.read<int>('tombstone'), 1);
      expect(row.read<int>('server_revision'), 5);
      expect(await cursor(), 9);
    },
  );
  test(
    'deletion keeps an unsent draft and creates a non-resurrectable marker',
    () async {
      await seed();
      await store.apply(
        page([entry(8, id, deleted: true)]),
        snapshotToken: token,
      );
      final row = await db
          .customSelect('SELECT * FROM metadata_copies')
          .getSingle();
      expect(row.read<int>('tombstone'), 1);
      expect(jsonDecode(row.read<String>('local_payload')), {'title': 'draft'});
      expect(await cursor(), 8);
    },
  );
  test(
    'same-revision disagreement rejects page instead of overwriting',
    () async {
      await seed(revision: 2);
      await expectLater(
        store.apply(page([entry(8, id)]), snapshotToken: token),
        throwsStateError,
      );
      expect(await cursor(), 7);
    },
  );
  test(
    'empty page requires an applied baseline and does not invent progress',
    () async {
      await store.apply(page([]), snapshotToken: token);
      expect(await cursor(), 7);
      await db.customStatement('UPDATE sync_cursors SET baseline_complete=0');
      await expectLater(
        store.apply(page([]), snapshotToken: token),
        throwsStateError,
      );
    },
  );
  test(
    'snapshot replacement at identical cursor fences an old response',
    () async {
      final latest = await replaceBaseline('SONG', {
        ...songChange(id, 5),
        'user_id': owner,
      });
      await expectLater(
        store.apply(page([entry(8, id)]), snapshotToken: token),
        throwsStateError,
      );
      await store.apply(page([entry(8, id)]), snapshotToken: latest);
      expect(
        (await db
                .customSelect('SELECT server_revision FROM metadata_copies')
                .getSingle())
            .read<int>('server_revision'),
        5,
      );
      expect(await cursor(), 8);
    },
  );
  test('initial permanent ledger prevents revival using entity_id, not ledger UUID', () async {
    final latest = await replaceBaseline('DELETION_LEDGER', {
      'id': id,
      'user_id': owner,
      'entity_type': 'SONG',
      'entity_id': other,
      'revision': 5,
      'object_generation': null,
      'purged_at': '2026-10-01T00:00:00Z',
    });
    await expectLater(
      store.apply(page([entry(8, other, revision: 6)]), snapshotToken: latest),
      throwsStateError,
    );
    expect(
      await db.customSelect('SELECT * FROM metadata_copies').get(),
      isEmpty,
    );
    expect(await cursor(), 7);
  });
  test('old delta installs permanent marker but preserves local draft and snapshot rows', () async {
    final latest = await replaceBaseline('DELETION_LEDGER', {
      'id': id,
      'user_id': owner,
      'entity_type': 'SONG',
      'entity_id': other,
      'revision': 5,
      'object_generation': null,
      'purged_at': '2026-10-01T00:00:00Z',
    });
    await db.customStatement(
      'INSERT INTO metadata_copies VALUES(?,?,?,?,?,?,0,0)',
      [
        owner,
        'SONG',
        other,
        1,
        jsonEncode(songChange(other, 1)),
        jsonEncode({'title': 'unsent draft'}),
      ],
    );
    final before =
        (await db.customSelect('SELECT * FROM snapshot_download_rows').get())
            .map((r) => r.data)
            .toList();
    await store.apply(page([entry(8, other)]), snapshotToken: latest);
    final row = await db
        .customSelect('SELECT * FROM metadata_copies')
        .getSingle();
    expect(row.read<int>('tombstone'), 1);
    expect(row.read<int>('server_revision'), 5);
    expect(jsonDecode(row.read<String>('server_payload')), {
      'id': other,
      'entity_type': 'SONG',
      'revision': 5,
      'status': 'DELETED',
      'deleted_at': '2026-10-01T00:00:00Z',
    });
    expect(jsonDecode(row.read<String>('local_payload')), {
      'title': 'unsent draft',
    });
    expect(await cursor(), 8);
    expect(
      (await db.customSelect('SELECT * FROM snapshot_download_rows').get())
          .map((r) => r.data)
          .toList(),
      before,
    );
  });
  test(
    'malformed deletion marker rolls back earlier changes and cursor',
    () async {
      final latest = await replaceBaseline('DELETION_LEDGER', {
        'id': id,
        'user_id': owner,
        'entity_type': 'SONG',
        'entity_id': other,
        'revision': 5,
        'object_generation': null,
        'purged_at': '2026-02-30T00:00:00Z',
      });
      await expectLater(
        store.apply(
          page([entry(8, id), entry(9, other)]),
          snapshotToken: latest,
        ),
        throwsFormatException,
      );
      expect(await cursor(), 7);
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
    },
  );
  test(
    'empty page still installs all baseline tombstones before accepting cursor',
    () async {
      final latest = await replaceBaseline('DELETION_LEDGER', {
        'id': id,
        'user_id': owner,
        'entity_type': 'SONG',
        'entity_id': other,
        'revision': 5,
        'object_generation': null,
        'purged_at': '2026-10-01T00:00:00Z',
      });
      await store.apply(page([]), snapshotToken: latest);
      final row = await db
          .customSelect('SELECT * FROM metadata_copies')
          .getSingle();
      expect(row.read<String>('entity_id'), other);
      expect(row.read<int>('tombstone'), 1);
      expect(row.readNullable<String>('local_payload'), isNull);
      expect(await cursor(), 7);
    },
  );
  for (final type in ['PLAYLIST', 'PLAYLIST_ITEM', 'CONDITION']) {
    test(
      'initial $type marker keeps draft and raw history with correct local kind',
      () async {
        final localType = type == 'CONDITION' ? 'RECORDING_CONDITION' : type;
        await db.customStatement(
          'INSERT INTO metadata_copies VALUES(?,?,?,?,?,?,?,0)',
          [
            owner,
            localType,
            other,
            1,
            '{"revision":1}',
            '{"note":"retained"}',
            0,
          ],
        );
        final latest = await replaceBaseline('DELETION_LEDGER', {
          'id': id,
          'user_id': owner,
          'entity_type': type,
          'entity_id': other,
          'revision': 5,
          'object_generation': null,
          'purged_at': '2026-10-01T00:00:00Z',
        });
        final before =
            (await db
                    .customSelect('SELECT * FROM snapshot_download_rows')
                    .get())
                .map((r) => r.data)
                .toList();
        await store.apply(page([]), snapshotToken: latest);
        final copy = await db
            .customSelect('SELECT * FROM metadata_copies')
            .getSingle();
        expect(copy.read<String>('entity_type'), localType);
        expect(copy.read<String>('entity_id'), other);
        expect(copy.read<int>('tombstone'), 1);
        expect(copy.read<int>('server_revision'), 5);
        expect(copy.read<String>('local_payload'), '{"note":"retained"}');
        final obsolete = {
          'change_seq': 8,
          'entity_type': type,
          'entity_id': other,
          'revision': 2,
          'operation': 'UPSERT',
          'payload': {'id': other, 'revision': 2},
        };
        await store.apply(page([obsolete]), snapshotToken: latest);
        expect(
          (await db
                  .customSelect('SELECT tombstone FROM metadata_copies')
                  .getSingle())
              .read<int>('tombstone'),
          1,
        );
        await expectLater(
          store.apply(
            page([
              {
                ...obsolete,
                'change_seq': 9,
                'revision': 6,
                'payload': {'id': other, 'revision': 6},
              },
            ], after: 8),
            snapshotToken: latest,
          ),
          throwsStateError,
        );
        expect(
          (await db.customSelect('SELECT * FROM snapshot_download_rows').get())
              .map((r) => r.data)
              .toList(),
          before,
        );
        expect(await cursor(), 8);
      },
    );
  }
  test('unsupported relation or asset aborts whole page without inventing revision', () async {
    for (final type in ['PLAYLIST_ITEM', 'RECORDING_ASSET']) {
      final unsupported = entry(9, other)..['entity_type'] = type;
      await expectLater(
        store.apply(page([entry(8, id), unsupported]), snapshotToken: token),
        throwsFormatException,
      );
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
      expect(await cursor(), 7);
    }
  });
  test(
    'recording edit delta preserves a prior saved file projection in SQLite',
    () async {
      final previous = {
        'id': id,
        'revision': 1,
        'file': recordingWire('RecordingSaved')['file'],
        'tier': 'A',
        'tag_ids': <String>[],
        'tags': <Object>[],
      };
      await db.customStatement(
        'INSERT INTO metadata_copies VALUES(?,?,?,?,?,?,0,0)',
        [owner, 'RECORDING', id, 1, jsonEncode(previous), jsonEncode(previous)],
      );
      final edited = entry(8, id)..['entity_type'] = 'RECORDING';
      edited['payload'] = {
        ...recordingWire('RecordingEdited'),
        'id': id,
        'revision': 2,
        'tier': null,
        'tag_ids': <String>[],
        'tags': <Object>[],
      };
      await store.apply(page([edited]), snapshotToken: token);
      final row = await db
          .customSelect('SELECT * FROM metadata_copies')
          .getSingle();
      final server = jsonDecode(row.read<String>('server_payload')) as Map;
      expect(server['file'], previous['file']);
      expect(server['tier'], isNull);
      expect(jsonDecode(row.read<String>('local_payload')), server);
      expect(await cursor(), 8);
    },
  );
  test('first recording delta preserves initial file and historical tags atomically', () async {
    final initial = {
      ...recordingWire('RecordingDraft'),
      'id': id,
      'revision': 1,
      'user_id': owner,
      'tier': 'B',
    };
    final file = recordingWire('RecordingSaved')['file'] as Map;
    final activeToken = await replaceBaseline(
      'RECORDING',
      initial,
      relations: {
        'RECORDING_FILE_SPEC': [
          {
            ...Map<String, Object?>.from(file),
            'recording_id': id,
            'user_id': owner,
          },
        ],
        'RECORDING_TAG': [
          {
            'recording_id': id,
            'user_id': owner,
            'tag_id': other,
            'name_snapshot': 'old name',
          },
        ],
      },
    );
    final snapshotBefore =
        (await db
                .customSelect(
                  'SELECT * FROM snapshot_download_rows ORDER BY entity,ordinal',
                )
                .get())
            .map((r) => r.data)
            .toList();
    final delta = entry(8, id)..['entity_type'] = 'RECORDING';
    delta['payload'] = {
      ...recordingWire('RecordingDraft'),
      'id': id,
      'revision': 2,
    };
    await store.apply(page([delta]), snapshotToken: activeToken);
    final row = await db
        .customSelect('SELECT * FROM metadata_copies')
        .getSingle();
    final server = jsonDecode(row.read<String>('server_payload')) as Map;
    expect(server['file'], file);
    expect(server['tier'], 'B');
    expect(server['tags'], [
      {'id': other, 'name_snapshot': 'old name'},
    ]);
    expect(server.containsKey('user_id'), isFalse);
    expect(await cursor(), 8);
    final clear = entry(9, id, revision: 3)..['entity_type'] = 'RECORDING';
    clear['payload'] = {
      ...recordingWire('RecordingEdited'),
      'id': id,
      'revision': 3,
      'tier': null,
      'tag_ids': <String>[],
      'tags': <Object>[],
    };
    await store.apply(page([clear], after: 8), snapshotToken: activeToken);
    final later = entry(10, id, revision: 4)..['entity_type'] = 'RECORDING';
    later['payload'] = {
      ...recordingWire('RecordingDraft'),
      'id': id,
      'revision': 4,
    };
    await store.apply(page([later], after: 9), snapshotToken: activeToken);
    final latest = jsonDecode(
      (await db
              .customSelect('SELECT server_payload FROM metadata_copies')
              .getSingle())
          .read<String>('server_payload'),
    ) as Map;
    expect(latest['file'], file);
    expect(latest['tag_ids'], isEmpty);
    expect(latest['tags'], isEmpty);
    expect(latest['tier'], isNull);
    expect(await cursor(), 10);
    expect(
      (await db
              .customSelect(
                'SELECT * FROM snapshot_download_rows ORDER BY entity,ordinal',
              )
              .get())
          .map((r) => r.data)
          .toList(),
      snapshotBefore,
    );
  });
  test(
    'invalid initial file refuses the whole page and leaves cursor unchanged',
    () async {
      final initial = {
        ...recordingWire('RecordingDraft'),
        'id': id,
        'revision': 1,
        'user_id': owner,
      };
      final activeToken = await replaceBaseline(
        'RECORDING',
        initial,
        relations: {
          'RECORDING_FILE_SPEC': [
            {'recording_id': id, 'user_id': owner, 'sha256': 'broken'},
          ],
        },
      );
      final delta = entry(9, id)..['entity_type'] = 'RECORDING';
      delta['payload'] = {
        ...recordingWire('RecordingDraft'),
        'id': id,
        'revision': 2,
      };
      await expectLater(
        store.apply(page([entry(8, other), delta]), snapshotToken: activeToken),
        throwsFormatException,
      );
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
      expect(await cursor(), 7);
    },
  );
  test(
    'empty delta projects initial song and retains unacknowledged local draft',
    () async {
      await seed(local: 'unsent');
      final latest = await replaceBaseline('SONG', {
        ...songChange(id, 5, title: 'fresh baseline'),
        'user_id': owner,
      });
      final rawBefore =
          (await db.customSelect('SELECT * FROM snapshot_download_rows').get())
              .map((r) => r.data)
              .toList();
      await store.apply(page([]), snapshotToken: latest);
      final copy =
          (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
              .data;
      expect(copy['server_revision'], 5);
      expect(
        jsonDecode(copy['server_payload'] as String)['title'],
        'fresh baseline',
      );
      expect(jsonDecode(copy['local_payload'] as String)['title'], 'unsent');
      expect(
        (await db.customSelect('SELECT * FROM snapshot_download_rows').get())
            .map((r) => r.data)
            .toList(),
        rawBefore,
      );
      expect(await cursor(), 7);
      await store.apply(page([]), snapshotToken: latest);
      expect(
        (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
            .data,
        copy,
      );
    },
  );
  test(
    'upgrade projects baseline even if old receiver already advanced cursor',
    () async {
      await seed(local: 'unsent');
      final latest = await replaceBaseline('SONG', {
        ...songChange(id, 5),
        'user_id': owner,
      });
      await db.customStatement('UPDATE sync_cursors SET last_change_seq=8');
      await store.apply(page([], after: 8), snapshotToken: latest);
      final copy =
          (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
              .data;
      expect(copy['server_revision'], 5);
      expect(jsonDecode(copy['local_payload'] as String)['title'], 'unsent');
      expect(await cursor(), 8);
    },
  );
  test(
    'initial tag projection strips raw metadata and preserves archive state',
    () async {
      final latest = await replaceBaseline('TAG', {
        'id': id,
        'user_id': owner,
        'revision': 2,
        'name': 'archived',
        'archived_at': '2026-10-01T00:00:00Z',
        'created_at': '2026-09-30T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      });
      await store.apply(page([]), snapshotToken: latest);
      final copy =
          (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
              .data;
      final payload = jsonDecode(copy['server_payload'] as String) as Map;
      expect(payload['archived_at'], '2026-10-01T00:00:00Z');
      expect(payload.containsKey('user_id'), isFalse);
      expect(payload.containsKey('created_at'), isFalse);
      expect(copy['local_payload'], copy['server_payload']);
    },
  );
  test(
    'initial projection neither rewinds newer receipt nor revives tombstone',
    () async {
      await seed(revision: 9);
      final latest = await replaceBaseline('SONG', {
        ...songChange(id, 5),
        'user_id': owner,
      });
      final before =
          (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
              .data;
      await store.apply(page([]), snapshotToken: latest);
      expect(
        (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
            .data,
        before,
      );
      await db.customStatement(
        'UPDATE metadata_copies SET server_revision=1,tombstone=1',
      );
      await store.apply(page([]), snapshotToken: latest);
      final row =
          (await db.customSelect('SELECT * FROM metadata_copies').getSingle())
              .data;
      expect(row['tombstone'], 1);
      expect(row['server_revision'], 1);
    },
  );
  test(
    'invalid later initial tag rolls back earlier song and cursor writes',
    () async {
      final latest = await replaceBaseline(
        'SONG',
        {...songChange(id, 5), 'user_id': owner},
        relations: {
          'TAG': [
            {
              'id': id,
              'user_id': owner,
              'revision': 1,
              'name': '',
              'archived_at': null,
              'updated_at': '2026-10-01T00:00:00Z',
            },
          ],
        },
      );
      await expectLater(
        store.apply(page([]), snapshotToken: latest),
        throwsFormatException,
      );
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
      expect(await cursor(), 7);
    },
  );
  test(
    'cursor write failure also rolls back applied business changes',
    () async {
      await db.customStatement(
        "CREATE TRIGGER reject_cursor BEFORE UPDATE ON sync_cursors BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(
        store.apply(page([entry(8, id)]), snapshotToken: token),
        throwsA(isA<Exception>()),
      );
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
      expect(await cursor(), 7);
    },
  );
}
