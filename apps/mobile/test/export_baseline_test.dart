import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'support/business_snapshot_fixture.dart';

class ExportFixtureTransport implements SnapshotTransport {
  ExportFixtureTransport(this.fixture);
  final Map<String, dynamic> fixture;
  bool corrupt = false, building = false;
  int calls = 0;
  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    requireCurrent();
    calls++;
    final id = (fixture['manifest'] as Map)['snapshot_token'];
    if (request.method == 'POST') {
      expect(request.path, '/v1/exports');
      expect(request.includeTrash, false);
      return SnapshotHttpResponse(
        202,
        jsonEncode({
          'export_id': id,
          'operation_id': '99999999-9999-4999-8999-999999999999',
          'status': 'BUILDING',
          'status_url': '/v1/exports/$id/manifest',
        }),
      );
    }
    expect(request.path, '/v1/exports/$id/manifest');
    if (building) return const SnapshotHttpResponse(202, '{}');
    final entity = request.query['entity'];
    final map = Map<String, dynamic>.from(
      entity == null
          ? fixture['manifest'] as Map
          : (fixture['pages'] as List).singleWhere((p) => p['entity'] == entity)
                as Map,
    );
    if (corrupt && entity == null) map['manifest_hash'] = '0' * 64;
    map.addAll({
      'export_id': id,
      'source_user_id': fixture['owner'],
      'include_trash': false,
    });
    return SnapshotHttpResponse(200, jsonEncode(map));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AccountStoreManager manager;
  late AccountStore store;
  late ExportFixtureTransport transport;
  late ExportBaselineReader reader;
  late String owner, token;
  final now = DateTime.utc(2026, 9, 30);
  bool current = true;
  Future<void> edit(int op, int song, String title) => store.saveEdit(
    LocalEdit(
      opId: 'aaaaaaaa-aaaa-4aaa-8aaa-${op.toString().padLeft(12, '0')}',
      entity: LocalEntity.song,
      entityId: 'bbbbbbbb-bbbb-4bbb-8bbb-${song.toString().padLeft(12, '0')}',
      operation: LocalOperation.create,
      baseRevision: 0,
      draft: {'title': title},
      changes: {'title': title},
    ),
  );
  setUp(() async {
    current = true;
    directory = await Directory.systemTemp.createTemp(
      'songrecord-export-baseline-',
    );
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
    );
    final fixture = businessSnapshotFixture();
    owner = fixture['owner'] as String;
    token = (fixture['manifest'] as Map)['snapshot_token'] as String;
    store = await manager.openAccount(owner);
    transport = ExportFixtureTransport(fixture);
    reader = ExportBaselineReader(
      store: store,
      transport: transport,
      clock: () => now,
      requireCurrent: () {
        if (!current) throw StateError('Account changed');
      },
      session: () async => AuthSession(
        userId: owner,
        deviceId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        accessToken: 'fixture',
        refreshToken: 'fixture',
        accessExpiresAt: now.add(const Duration(hours: 1)),
        refreshExpiresAt: now.add(const Duration(days: 1)),
      ),
    );
  });
  tearDown(() async {
    await manager.logout();
    await directory.delete(recursive: true);
  });
  test(
    'online snapshot and local drafts have separate immutable cutoffs',
    () async {
      await edit(1, 1, 'before cutoff');
      final handle = await reader.request(
        operationId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        includeTrash: false,
      );
      final frozen = await reader.freezeReady(handle);
      expect(frozen.online, isTrue);
      expect(frozen.entries, isNotEmpty);
      expect(
        frozen.manifest!.cursor,
        transport.fixture['manifest']['snapshot_cursor'],
      );
      await edit(2, 2, 'after cutoff');
      expect((frozen.local['changes'] as List).length, 1);
      expect(jsonEncode(frozen.local), contains('before cutoff'));
      expect(jsonEncode(frozen.local), isNot(contains('after cutoff')));
      frozen.local.clear();
      expect(frozen.local['source_user_id'], owner);
      expect((await store.captureExportLocal())['changes'], hasLength(2));
      expect(frozen.entries.first.payload['user_id'], owner);
    },
  );
  test('offline partial retains drafts and null unconfirmed cursor without network', () async {
    await edit(1, 1, 'offline');
    final result = await reader.offline(includeTrash: false);
    expect(result.online, isFalse);
    expect(result.manifest, isNull);
    final baseline = (result.local['baseline'] as List).single as Map;
    expect(baseline['last_change_seq'], isNull);
    expect(baseline['baseline_complete'], 0);
    expect(result.local['changes'], hasLength(1));
    expect(transport.calls, 0);
  });
  test(
    'building or invalid final hash never releases a partial baseline',
    () async {
      final handle = ExportHandle(token, false);
      transport.building = true;
      await expectLater(
        reader.freezeReady(handle),
        throwsA(isA<ExportNotReady>()),
      );
      transport.building = false;
      transport.corrupt = true;
      await expectLater(reader.freezeReady(handle), throwsFormatException);
      expect((await store.captureExportLocal())['copies'], isEmpty);
    },
  );
  test('conflict response and local draft stay frozen without acknowledging the queue', () async {
    await edit(1, 1, 'conflicted local draft');
    // Seed a persisted conflict independently of the dispatcher's wire eligibility.
    final paths = await AccountPaths.create(
      directory,
      owner,
      AppEnvironment.dev,
    );
    final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
    try {
      db.execute(
        "UPDATE local_mutations SET queue_state='CONFLICT',server_response=?",
        [
          jsonEncode({
            'code': 'REVISION_CONFLICT',
            'current': {'revision': 9, 'title': 'server conflict'},
          }),
        ],
      );
    } finally {
      db.close();
    }
    final frozen = await reader.offline(includeTrash: false);
    final change = (frozen.local['changes'] as List).single as Map;
    expect(change['queue_state'], 'CONFLICT');
    expect(change['server_response'], contains('server conflict'));
    expect(change['payload'], contains('conflicted local draft'));
    await edit(2, 2, 'later draft');
    expect(frozen.local['changes'], hasLength(1));
    final pending = await store.pendingMutations();
    expect(pending, hasLength(2));
    expect(pending.where((m) => m.state == 'CONFLICT'), hasLength(1));
  });
  test(
    'account fence rejects capture and network without touching drafts',
    () async {
      await edit(1, 1, 'preserved');
      current = false;
      await expectLater(
        reader.freezeReady(ExportHandle(token, false)),
        throwsStateError,
      );
      await expectLater(reader.offline(includeTrash: false), throwsStateError);
      expect(transport.calls, 0);
      expect((await store.captureExportLocal())['changes'], hasLength(1));
    },
  );
}
