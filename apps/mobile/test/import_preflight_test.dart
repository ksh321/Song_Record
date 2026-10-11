import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';

import 'support/business_snapshot_fixture.dart';

class ImportTransport implements SnapshotTransport {
  ImportTransport(this.fixture);
  final Map<String, dynamic> fixture;
  int calls = 0;
  bool corrupt = false, wrongOwner = false, building = false;
  void Function()? duringSend;
  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    calls++;
    duringSend?.call();
    final token = (fixture['manifest'] as Map)['snapshot_token'];
    if (request.method == 'POST') {
      expect(request.path, '/v1/imports/preflight');
      expect(request.sourceUserId, session.userId);
      return SnapshotHttpResponse(
        202,
        jsonEncode({
          'snapshot_token': token,
          'operation_id': '99999999-9999-4999-8999-999999999999',
          'status': 'BUILDING',
          'status_url': '/v1/sync/snapshots/$token',
        }),
      );
    }
    if (building) return const SnapshotHttpResponse(202, '{}');
    final entity = request.query['entity'];
    final map = Map<String, dynamic>.from(
      entity == null
          ? fixture['manifest'] as Map
          : (fixture['pages'] as List).singleWhere((p) => p['entity'] == entity)
                as Map,
    );
    if (corrupt && entity == null) map['manifest_hash'] = '0' * 64;
    if (wrongOwner && entity != null) {
      final list = map['entries'] as List;
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        final payload = Map<String, dynamic>.from(row['payload'] as Map);
        payload['user_id'] = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        row['payload'] = payload;
        map['entries'] = [row, ...list.skip(1)];
      }
    }
    return SnapshotHttpResponse(200, jsonEncode(map));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AccountStoreManager manager;
  late AccountStore store;
  late ImportTransport transport;
  late ImportPreflight preflight;
  late String owner, token;
  bool current = true;
  String? sessionOwner;
  final now = DateTime.utc(2026, 9, 30);
  ExportManifest backup(String user) => ExportManifest(
    exportId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    sourceUserId: user,
    createdAt: now,
    localCutoffAt: now,
    online: false,
    includeTrash: false,
    snapshotCursor: null,
    serverBaselineComplete: false,
    serverConfirmedAt: null,
    serverCapturedAt: null,
    metadataCount: 0,
    files: const [],
  );
  setUp(() async {
    current = true;
    sessionOwner = null;
    dir = await Directory.systemTemp.createTemp('songrecord-import-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
    );
    final f = businessSnapshotFixture();
    owner = f['owner'] as String;
    replaceBusinessSnapshotRows(f, 'DELETION_LEDGER', [
      {
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'user_id': owner,
        'entity_type': 'SONG',
        'entity_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'purged_at': '2026-09-29T00:00:00.000Z',
      },
    ]);
    token = (f['manifest'] as Map)['snapshot_token'] as String;
    store = await manager.openAccount(owner);
    transport = ImportTransport(f);
    preflight = ImportPreflight(
      store: store,
      transport: transport,
      clock: () => now,
      requireCurrent: () {
        if (!current) throw StateError('Changed');
      },
      session: () async => AuthSession(
        userId: sessionOwner ?? owner,
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
    await dir.delete(recursive: true);
  });
  test(
    'all server entities and deletion markers verified without applying to DB',
    () async {
      final before = jsonEncode(await store.captureExportLocal());
      expect(
        await preflight.request(
          backup(owner),
          'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        ),
        token,
      );
      final result = await preflight.readReady(token);
      expect(result.owner, owner);
      expect(
        result.manifest.cursor,
        (transport.fixture['manifest'] as Map)['snapshot_cursor'],
      );
      expect(result.entries.any((e) => e.entity == 'DELETION_LEDGER'), isTrue);
      expect(
        jsonEncode(await store.captureExportLocal()).replaceAll(
          RegExp(r'"local_cutoff_at":"[^"]+"'),
          '"local_cutoff_at":"cutoff"',
        ),
        before.replaceAll(
          RegExp(r'"local_cutoff_at":"[^"]+"'),
          '"local_cutoff_at":"cutoff"',
        ),
      );
    },
  );
  test('other backup owner rejected before any server call', () async {
    await expectLater(
      preflight.request(
        backup('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      ),
      throwsFormatException,
    );
    expect(transport.calls, 0);
  });
  test(
    'authenticated session mismatch rejected independently from ZIP',
    () async {
      sessionOwner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      await expectLater(
        preflight.request(
          backup(owner),
          'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        ),
        throwsStateError,
      );
      expect(transport.calls, 0);
    },
  );
  test(
    'account switch during response and malformed integrity fail closed',
    () async {
      transport.duringSend = () => current = false;
      await expectLater(preflight.readReady(token), throwsStateError);
      current = true;
      transport.duringSend = null;
      transport.corrupt = true;
      await expectLater(preflight.readReady(token), throwsFormatException);
    },
  );
  test(
    'foreign page owner rejected and BUILDING cannot become ready',
    () async {
      transport.wrongOwner = true;
      await expectLater(preflight.readReady(token), throwsFormatException);
      transport.wrongOwner = false;
      transport.building = true;
      await expectLater(
        preflight.readReady(token),
        throwsA(isA<ImportNotReady>()),
      );
    },
  );
}
