import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/snapshot_download_store.dart';

void main() {
  const owner = '11111111-1111-4111-8111-111111111111',
      token = '22222222-2222-4222-8222-222222222222',
      rec = '33333333-3333-4333-8333-333333333333',
      tag1 = '44444444-4444-4444-8444-444444444444',
      tag2 = '55555555-5555-4555-8555-555555555555';
  late AccountDatabase db;
  late SnapshotDownloadStore store;
  var active = true;
  setUp(() async {
    db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    active = true;
    store = SnapshotDownloadStore(
      db,
      clock: () => DateTime.utc(2030),
      requireActive: () {
        if (!active) throw StateError('expired account');
      },
    );
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> seed({bool orphan = false, bool duplicate = false}) async {
    final manifest =
        (jsonDecode(
              File('../../fixtures/contracts/snapshot-wire.json')
                  .readAsStringSync(),
            ) as Map)['manifest']
            as Map;
    (manifest['entity_counts'] as Map).updateAll(
      (key, value) => switch (key) {
        'RECORDING' => orphan ? 0 : 1,
        'RECORDING_FILE_SPEC' => 1,
        'RECORDING_TAG' => 2,
        _ => 0,
      },
    );
    await db.customStatement(
      'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,7,1800000,0)',
      [token, owner, jsonEncode(manifest)],
    );
    Future<void> row(
      String entity,
      int ordinal,
      Map<String, Object?> payload,
    ) => db.customStatement(
      'INSERT INTO snapshot_download_rows VALUES(?,?,?,?,?,?)',
      [
        token,
        owner,
        entity,
        ordinal,
        rec,
        jsonEncode({'user_id': owner, ...payload}),
      ],
    );
    if (!orphan) await row('RECORDING', 1, {'id': rec, 'revision': 3});
    await row('RECORDING_FILE_SPEC', 1, {
      'recording_id': rec,
      'sha256': 'synthetic',
    });
    await row('RECORDING_TAG', 1, {
      'recording_id': rec,
      'tag_id': tag1,
      'name_snapshot': 'historical one',
    });
    await row('RECORDING_TAG', 2, {
      'recording_id': rec,
      'tag_id': duplicate ? tag1 : tag2,
      'name_snapshot': 'historical two',
    });
    await db.customStatement("UPDATE snapshot_downloads SET state='VERIFIED'");
    await db.customStatement("UPDATE snapshot_downloads SET state='APPLIED'");
    await db.customStatement('INSERT INTO snapshot_baseline VALUES(1,?,?)', [
      token,
      owner,
    ]);
  }

  test(
    'absence of baseline differs from absent recording in a baseline',
    () async {
      expect(await store.recordingBaseline(rec), isNull);
      await seed();
      final absent = (await store.recordingBaseline(tag1))!;
      expect(absent.recording, isNull);
      expect(absent.file, isNull);
      expect(absent.tags, isEmpty);
    },
  );
  test(
    'file and both repeated-resource tag rows share pinned token and cursor',
    () async {
      await seed();
      final bundle = (await store.recordingBaseline(
        rec,
        expectedToken: token,
      ))!;
      expect(bundle.token, token);
      expect(bundle.cursor, 7);
      expect(bundle.recording!.payload['revision'], 3);
      expect(bundle.file!.payload['recording_id'], rec);
      expect(bundle.tags.map((entry) => entry.payload['tag_id']), [tag1, tag2]);
      expect(bundle.tags.map((entry) => entry.payload['name_snapshot']), [
        'historical one',
        'historical two',
      ]);
      expect(() => bundle.tags.clear(), throwsUnsupportedError);
      bundle.tags.first.payload['name_snapshot'] = 'changed';
      expect(bundle.tags.first.payload['name_snapshot'], 'historical one');
      expect(bundle.toString(), isNot(contains('historical')));
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
    },
  );
  test('applied baseline remains readable after download expiry but stale account does not', () async {
    await seed();
    expect(await store.recordingBaseline(rec), isNotNull);
    await expectLater(
      store.recordingBaseline(rec, expectedToken: owner),
      throwsStateError,
    );
    active = false;
    await expectLater(store.recordingBaseline(rec), throwsStateError);
  });
  test('orphan relation refuses to invent a parent recording', () async {
    await seed(orphan: true);
    await expectLater(store.recordingBaseline(rec), throwsStateError);
  });
  test(
    'duplicate tag relationship is rejected without collapsing rows',
    () async {
      await seed(duplicate: true);
      await expectLater(store.recordingBaseline(rec), throwsStateError);
    },
  );
}
