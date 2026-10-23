import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/snapshot_business_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/playlist_library_order_receipt.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'auth_session_test.dart' as fixtures;
import 'metadata_dispatcher_test.dart' show FakeTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'library order uses one immutable request and survives receipt and reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('library-order-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      const owner = '00000000-0000-4000-8000-000000002504';
      final server = <String, Map<String, dynamic>>{};
      MutationRequest? orderRequest;
      MutationResponse? orderResponse;
      final transport = FakeTransport((request) async {
        final body = jsonDecode(request.body) as Map;
        if (request.path.endsWith('/library-order')) {
          if (orderResponse != null) {
            expect(request.hash, orderRequest!.hash);
            expect(request.mutation.opId, orderRequest!.mutation.opId);
            return orderResponse!;
          }
          orderRequest = request;
          final ordered = <Map<String, dynamic>>[];
          for (final entry in body['ordered_playlists'] as List) {
            final old = server[entry['id']]!;
            expect(old['revision'], entry['base_revision']);
            final row = {
              ...old,
              'revision': (old['revision'] as int) + 1,
              'display_order': ordered.length,
            };
            server[row['id'] as String] = row;
            ordered.add(row);
          }
          orderResponse = MutationResponse(
            200,
            jsonEncode({
              'playlist': server[request.mutation.entityId],
              'playlists': ordered,
            }),
          );
          return const MutationResponse(503, '{}');
        }
        final row = <String, dynamic>{
          'id': request.mutation.entityId,
          'name': body['name'],
          'icon': body['icon'],
          'display_order': server.length,
          'revision': 1,
          'deleted_at': null,
          'updated_at': '2026-10-23T00:00:00Z',
        };
        server[row['id'] as String] = row;
        return MutationResponse(201, jsonEncode(row));
      });
      try {
        var repo = LocalRepository(await manager.openAccount(owner));
        var library = PlaylistLibrary(repo);
        await library.create('첫 목록', icon: 'heart')();
        await library.create('둘째 목록', icon: 'star')();
        await repo.dispatch(
          transport: transport,
          session: () async => fixtures.session(user: owner),
        );
        final before = await library.load();
        final ids = before
            .map((r) => r['id'] as String)
            .toList()
            .reversed
            .toList();
        await expectLater(
          library.reorderLibrary(before, [ids.first, ids.first]),
          throwsStateError,
        );
        expect(await repo.pendingWork(), isEmpty);
        await library.reorderLibrary(before, ids);
        final pending = (await repo.pendingWork()).single;
        expect((await library.load()).map((r) => r['id']), ids);
        await manager.logout();
        repo = LocalRepository(await manager.openAccount(owner));
        library = PlaylistLibrary(repo);
        expect((await repo.pendingWork()).single.payload, pending.payload);
        expect((await library.load()).map((r) => r['id']), ids);
        await repo.dispatch(
          transport: transport,
          session: () async => fixtures.session(user: owner),
        );
        expect((await repo.pendingWork()).single.state, 'RETRY');
        expect(
          await repo.retryMutation(pending.opId, expectedAttempt: 1),
          isTrue,
        );
        await repo.dispatch(
          transport: transport,
          session: () async => fixtures.session(user: owner),
        );
        expect((await library.load()).map((r) => r['id']), ids);
        expect((await library.load()).map((r) => r['name']), ['둘째 목록', '첫 목록']);
        expect((await library.load()).map((r) => r['icon']), ['star', 'heart']);
        expect(await repo.pendingWork(), isEmpty);
        final changed = jsonDecode(orderResponse!.body) as Map<String, dynamic>;
        (changed['playlists'] as List).first['display_order'] = 5;
        expect(
          () => decodePlaylistLibraryOrder(
            orderRequest!,
            MutationResponse(200, jsonEncode(changed)),
          ),
          throwsFormatException,
        );
        await manager.logout();
        library = PlaylistLibrary(
          LocalRepository(await manager.openAccount(owner)),
        );
        expect((await library.load()).map((r) => r['id']), ids);
        await manager.openAccount('00000000-0000-4000-8000-000000002505');
        await expectLater(library.load(), throwsStateError);
      } finally {
        await manager.logout();
        await root.delete(recursive: true);
      }
    },
  );

  test('v13 upgrade preserves rows and rejected order requires explicit durable dismissal', () async {
    final root = await Directory.systemTemp.createTemp(
      'library-order-rejection-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    const owner = '00000000-0000-4000-8000-000000002514';
    try {
      var store = await manager.openAccount(owner);
      var repo = LocalRepository(store);
      var library = PlaylistLibrary(repo);
      await library.create('하나', icon: 'heart')();
      await library.create('둘', icon: 'star')();
      final create = FakeTransport((request) async {
        final body = jsonDecode(request.body) as Map;
        return MutationResponse(
          201,
          jsonEncode({
            'id': request.mutation.entityId,
            'name': body['name'],
            'icon': body['icon'],
            'display_order': 0,
            'revision': 1,
            'deleted_at': null,
            'updated_at': '2026-10-23T00:00:00Z',
          }),
        );
      });
      await repo.dispatch(
        transport: create,
        session: () async => fixtures.session(user: owner),
      );
      final before = await store.recoveryData();
      await manager.logout();
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
      try {
        // Reconstruct the immediately preceding schema: only v14's new empty
        // decision table/trigger are removed. Existing data and wire stay intact.
        db.execute('DROP TRIGGER playlist_order_dismissed_request_immutable');
        db.execute('DROP TABLE playlist_order_dismissals');
        db.execute('PRAGMA user_version=13');
      } finally {
        db.close();
      }
      store = await manager.openAccount(owner);
      repo = LocalRepository(store);
      library = PlaylistLibrary(repo);
      final after = jsonDecode(await store.recoveryData()) as Map;
      final original = jsonDecode(before) as Map;
      expect(after['tables'], original['tables']);
      final rows = await library.load();
      final ids = rows.map((r) => r['id'] as String).toList().reversed.toList();
      await library.reorderLibrary(rows, ids);
      final unattempted = (await repo.pendingWork()).single;
      await expectLater(
        repo.acceptLatestPlaylistOrder(unattempted),
        throwsStateError,
      );
      final rejected = FakeTransport(
        (request) async => const MutationResponse(
          409,
          '{"error":{"code":"PLAYLIST_ORDER_CHANGED"}}',
        ),
      );
      await repo.dispatch(
        transport: rejected,
        session: () async => fixtures.session(user: owner),
      );
      final failed = (await repo.pendingWork()).single;
      expect((await library.rejectedOrder())!.opId, failed.opId);
      await expectLater(library.reorderLibrary(rows, ids), throwsStateError);
      final evidence =
          (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
      await repo.acceptLatestPlaylistOrder(failed);
      expect(await repo.pendingWork(), isEmpty);
      expect((await repo.pending()).single.state, 'CONFLICT');
      final decided =
          (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
      for (final name in [
        'local_mutations',
        'mutation_wire_requests',
        'mutation_retry_controls',
      ]) {
        expect(decided[name], evidence[name]);
      }
      expect(decided['playlist_order_dismissals'], hasLength(1));
      await expectLater(
        repo.acceptLatestPlaylistOrder(failed),
        throwsStateError,
      );
      await manager.logout();
      final check = sqlite.sqlite3.open((await paths.databaseFile()).path);
      try {
        expect(
          () => check.execute('DELETE FROM playlist_order_dismissals'),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          () => check.execute(
            'UPDATE playlist_order_dismissals SET decided_at=0',
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          () => check.execute(
            "UPDATE local_mutations SET queue_state='RETRY' WHERE op_id=?",
            [failed.opId],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      } finally {
        check.close();
      }
      // A discarded request remains in history but must not freeze future pulls.
      final receiver = AccountDatabase(
        NativeDatabase(await paths.databaseFile()),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      try {
        await receiver.verifyReady();
        final copy = (decided['metadata_copies'] as List).firstWhere(
          (r) => r['entity_id'] == failed.entityId,
        ) as Map;
        final updated = {
          ...jsonDecode(copy['server_payload'] as String)
              as Map<String, dynamic>,
          'name': '다른 기기에서 변경',
          'revision': 2,
          'display_order': 5,
        };
        await SnapshotBusinessStore(
          receiver,
          requireActive: () {},
          clock: DateTime.now,
        ).writeCopy('PLAYLIST', failed.entityId, 2, jsonEncode(updated), false);
        final received = await receiver
            .customSelect(
              "SELECT local_payload FROM metadata_copies WHERE entity_id='${failed.entityId}'",
            )
            .getSingle();
        expect(
          jsonDecode(received.read<String>('local_payload'))['name'],
          '다른 기기에서 변경',
        );
      } finally {
        await receiver.close();
      }
      store = await manager.openAccount(owner);
      repo = LocalRepository(store);
      library = PlaylistLibrary(repo);
      expect(await repo.pendingWork(), isEmpty);
      expect(await library.rejectedOrder(), isNull);
      await library.reorderLibrary(await library.load(), ids);
      expect((await repo.pendingWork()).single.opId, isNot(failed.opId));
      await manager.openAccount('00000000-0000-4000-8000-000000002515');
      await expectLater(
        repo.acceptLatestPlaylistOrder(failed),
        throwsStateError,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
