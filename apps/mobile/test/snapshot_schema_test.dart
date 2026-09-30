import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  const owner = '11111111-1111-4111-8111-111111111111';
  const token = '22222222-2222-4222-8222-222222222222';
  const resource = '33333333-3333-4333-8333-333333333333';
  late AccountDatabase db;
  late Map<String, dynamic> fixture;
  setUp(() async {
    db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    fixture = jsonDecode(
      File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> download() => db.customStatement(
    'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,7,1800000,0)',
    [token, owner, jsonEncode(fixture['manifest'])],
  );
  Future<void> row({String user = owner}) => db.customStatement(
    "INSERT INTO snapshot_download_rows VALUES(?,?,'SONG',1,?,?)",
    [
      token,
      user,
      resource,
      jsonEncode({'id': resource, 'user_id': user}),
    ],
  );
  test(
    'rows bind to account and remain separate from baseline and edits',
    () async {
      await download();
      await row();
      expect(
        await db.customSelect('SELECT * FROM snapshot_baseline').get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT * FROM metadata_copies').get(),
        isEmpty,
      );
      expect(
        (await db
                .customSelect('SELECT baseline_complete FROM sync_cursors')
                .getSingle())
            .read<int>('baseline_complete'),
        0,
      );
      await expectLater(
        row(user: resource),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement(
          "UPDATE snapshot_download_rows SET canonical_payload='{}'",
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO snapshot_download_rows SELECT * FROM snapshot_download_rows',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    },
  );
  test(
    'manifest is immutable and baseline requires forward applied state',
    () async {
      await download();
      await row();
      await expectLater(
        db.customStatement('UPDATE snapshot_downloads SET expires_at=9999999'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO snapshot_downloads SELECT * FROM snapshot_downloads',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement('INSERT INTO snapshot_baseline VALUES(1,?,?)', [
          token,
          owner,
        ]),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement("UPDATE snapshot_downloads SET state='APPLIED'"),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await db.customStatement(
        "UPDATE snapshot_downloads SET state='VERIFIED'",
      );
      await expectLater(
        db.customStatement('DELETE FROM snapshot_download_rows'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement("UPDATE snapshot_downloads SET state='RECEIVING'"),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await db.customStatement("UPDATE snapshot_downloads SET state='APPLIED'");
      await db.customStatement('INSERT INTO snapshot_baseline VALUES(1,?,?)', [
        token,
        owner,
      ]);
      await expectLater(
        db.customStatement('DELETE FROM snapshot_downloads'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        await db.customSelect('SELECT * FROM snapshot_download_rows').get(),
        hasLength(1),
      );
    },
  );
  test('progress rejects null cursor and cannot move backward or replace history', () async {
    await download();
    await expectLater(
      db.customStatement(
        "INSERT INTO snapshot_download_progress VALUES(?,'SONG',1,NULL,0)",
        [token],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      "INSERT INTO snapshot_download_progress VALUES(?,'SONG',1,'sp1.next',0)",
      [token],
    );
    await expectLater(
      db.customStatement(
        'UPDATE snapshot_download_progress SET last_ordinal=0',
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await expectLater(
      db.customStatement(
        'INSERT OR REPLACE INTO snapshot_download_progress SELECT * FROM snapshot_download_progress',
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    await db.customStatement(
      'UPDATE snapshot_download_progress SET last_ordinal=2,next_cursor=NULL,finished=1',
    );
    await expectLater(
      db.customStatement(
        "UPDATE snapshot_download_progress SET last_ordinal=3,next_cursor='sp1.next',finished=0",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });
  test(
    'discarding only an unfinished download cascades its derived rows',
    () async {
      await download();
      await row();
      await db.customStatement(
        "INSERT INTO snapshot_download_progress VALUES(?,'SONG',1,NULL,1)",
        [token],
      );
      await db.customStatement(
        'DELETE FROM snapshot_downloads WHERE snapshot_token=?',
        [token],
      );
      for (final table in [
        'snapshot_download_rows',
        'snapshot_download_progress',
      ]) {
        expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
      }
      expect(
        await db.customSelect('SELECT * FROM local_account').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM sync_cursors').get(),
        hasLength(1),
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
  test(
    'download rows and page cursor survive closing and reopening the file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sr-snapshot-resume-',
      );
      final file = File('${directory.path}/account.sqlite');
      AccountDatabase open() => AccountDatabase(
        NativeDatabase(file),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      var disk = open();
      try {
        await disk.verifyReady();
        await disk.customStatement(
          'INSERT INTO snapshot_downloads(snapshot_token,user_id,manifest_json,snapshot_cursor,expires_at,created_at) VALUES(?,?,?,7,1800000,0)',
          [token, owner, jsonEncode(fixture['manifest'])],
        );
        await disk.customStatement(
          "INSERT INTO snapshot_download_rows VALUES(?,?,'SONG',1,?,?)",
          [
            token,
            owner,
            resource,
            jsonEncode({'id': resource, 'user_id': owner}),
          ],
        );
        await disk.customStatement(
          "INSERT INTO snapshot_download_progress VALUES(?,'SONG',1,'sp1.next',0)",
          [token],
        );
        await disk.close();
        disk = open();
        await disk.verifyReady();
        expect(
          (await disk
                  .customSelect(
                    'SELECT next_cursor FROM snapshot_download_progress',
                  )
                  .getSingle())
              .read<String>('next_cursor'),
          'sp1.next',
        );
        expect(
          await disk.customSelect('SELECT * FROM snapshot_download_rows').get(),
          hasLength(1),
        );
        expect(
          await disk.customSelect('SELECT * FROM snapshot_baseline').get(),
          isEmpty,
        );
        expect(
          (await disk
                  .customSelect('SELECT baseline_complete FROM sync_cursors')
                  .getSingle())
              .read<int>('baseline_complete'),
          0,
        );
      } finally {
        await disk.close();
        expect(
          directory.path.split(Platform.pathSeparator).last,
          startsWith('sr-snapshot-resume-'),
        );
        await directory.delete(recursive: true);
      }
    },
  );
  test('failed page transaction leaves no partial rows or progress', () async {
    await download();
    await expectLater(
      db.transaction(() async {
        await row();
        await db.customStatement(
          "INSERT INTO snapshot_download_progress VALUES(?,'SONG',1,NULL,1)",
          [token],
        );
        throw StateError('synthetic interruption');
      }),
      throwsStateError,
    );
    expect(
      await db.customSelect('SELECT * FROM snapshot_download_rows').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM snapshot_download_progress').get(),
      isEmpty,
    );
  });
}
