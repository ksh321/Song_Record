import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'auth_session_test.dart' as fixtures;
import 'metadata_dispatcher_test.dart' show FakeTransport;

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('duplicate names, offline rename/delete followups, replay and restart preserve durable queue and account scope', () async {
    final root = await Directory.systemTemp.createTemp('p19-library-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      var store = await manager.openAccount(id(1));
      var repo = LocalRepository(store);
      var library = PlaylistLibrary(repo);
      final save = library.create(' 오늘 ');
      await save();
      await save();
      await library.create('오늘')();
      expect(await library.load(), hasLength(2));
      final a = (await library.load()).first;
      await library.rename(a, '새 이름')();
      final updated = (await library.load()).first;
      await library.delete(updated)();
      expect(await library.load(), hasLength(1));
      final methods = <String>[];
      final transport = FakeTransport((request) async {
        methods.add(request.method);
        final body = jsonDecode(request.body) as Map;
        final revision = request.mutation.baseRevision + 1;
        return MutationResponse(
          request.method == 'POST' ? 201 : 200,
          jsonEncode(
            request.method == 'DELETE'
                ? {
                    'id': request.mutation.entityId,
                    'status': 'DELETED',
                    'revision': revision,
                    'deleted_at': '2026-10-11T00:00:00Z',
                  }
                : {
                    'id': request.mutation.entityId,
                    'name': body['name'],
                    'revision': revision,
                    'deleted_at': null,
                    'updated_at': '2026-10-11T00:00:00Z',
                  },
          ),
        );
      });
      expect(
        await repo.dispatch(
          transport: transport,
          session: () async => fixtures.session(user: id(1)),
        ),
        4,
      );
      expect(methods.where((x) => x == 'DELETE'), hasLength(1));
      expect(await library.load(), hasLength(1));
      expect(
        (await repo.read(LocalEntity.playlist, a['id'] as String))!.tombstone,
        isTrue,
      );
      store = await manager.openAccount(id(2));
      expect(await PlaylistLibrary(LocalRepository(store)).load(), isEmpty);
      await expectLater(library.create('old account')(), throwsStateError);
      store = await manager.openAccount(id(1));
      expect(
        (await PlaylistLibrary(LocalRepository(store)).load()).single['name'],
        '오늘',
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('v12 upgrade preserves immutable wire and queued playlist draft', () async {
    final root = await Directory.systemTemp.createTemp('p19-v12-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      var store = await manager.openAccount(id(1));
      var repo = LocalRepository(store);
      final library = PlaylistLibrary(repo);
      await library.create('오늘')();
      await library.rename((await library.load()).single, '보존 이름')();
      final request = await store.claimMutation();
      expect(request, isNotNull);
      await manager.logout();
      final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
      final file = await paths.databaseFile();
      final db = sqlite.sqlite3.open(file.path);
      final before = db
          .select('SELECT * FROM mutation_wire_requests')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      try {
        final triggers = db.select(
          "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND instr(sql,'mutation_wire_requests')>0",
        );
        db.execute(
          'CREATE TEMP TABLE wire_copy AS SELECT * FROM mutation_wire_requests',
        );
        for (final t in triggers) {
          db.execute('DROP TRIGGER "${t['name']}"');
        }
        db.execute('DROP TABLE mutation_wire_requests');
        db.execute(
          "CREATE TABLE mutation_wire_requests(op_id TEXT PRIMARY KEY REFERENCES local_mutations(op_id),contract_version TEXT NOT NULL,http_method TEXT NOT NULL CHECK(http_method IN ('POST','PATCH','PUT')),relative_path TEXT NOT NULL,body_json TEXT NOT NULL,wire_hash TEXT NOT NULL)",
        );
        db.execute(
          'INSERT INTO mutation_wire_requests SELECT * FROM wire_copy',
        );
        for (final t in triggers) {
          db.execute(t['sql'] as String);
        }
        db.execute('PRAGMA user_version=12');
      } finally {
        db.close();
      }
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(check.select('PRAGMA user_version').single.values.single, 13);
        expect(
          check
              .select('SELECT * FROM mutation_wire_requests')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          before,
        );
        expect(
          check
              .select(
                "SELECT sql FROM sqlite_master WHERE name='recording_followup_valid_insert'",
              )
              .single['sql'],
          contains("'PLAYLIST'"),
        );
      } finally {
        check.close();
      }
      expect((await PlaylistLibrary(repo).load()).single['name'], '보존 이름');
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });

  test('invalid or empty names never create a command', () async {
    final root = await Directory.systemTemp.createTemp('p19-validation-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    try {
      final library = PlaylistLibrary(
        LocalRepository(await manager.openAccount(id(1))),
      );
      for (final name in [' ', 'a' * 101]) {
        expect(() => library.create(name), throwsArgumentError);
      }
      await library.create('😀' * 100)();
      expect(await library.load(), hasLength(1));
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
