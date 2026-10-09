import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/widgets/recording_file_status_card.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  final owner = preservationId(1), id = preservationId(2);
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-status-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<void> seed({
    String cloud = 'NONE',
    String? reason,
    bool pending = true,
    bool current = false,
    bool tombstone = false,
    bool draft = false,
    bool invalid = false,
  }) async {
    await manager.logout();
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    final record = jsonEncode({
      'id': id,
      'user_id': owner,
      'revision': 1,
      'lifecycle_state': 'ACTIVE',
      'metadata_state': 'SAVED',
    });
    for (final row in [
      ['RECORDING', id, record],
      [
        'RECORDING_ASSET',
        id,
        jsonEncode({
          'recording_id': id,
          'user_id': owner,
          'cloud_state': cloud,
          'blocked_reason': reason,
          'generation': preservationId(3),
          'verified_size': 4,
          'sha256': invalid ? 'bad' : sha256.convert(bytes).toString(),
          'stored_at': '2026-10-09T00:00:00Z',
          'cloud_revision': 1,
        }),
      ],
      [
        'PIN_SLOT',
        owner,
        jsonEncode({
          'user_id': owner,
          'slot_no': 1,
          'current_recording_id': current ? id : null,
          'pending_recording_id': pending ? id : null,
          'revision': 1,
        }),
      ],
    ]) {
      await db.customStatement(
        'INSERT OR REPLACE INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,tombstone,updated_at) VALUES(?,?,?,1,?,?,?,1)',
        [
          owner,
          row[0],
          row[1],
          row[2],
          row[0] == 'RECORDING' && draft
              ? jsonEncode({'note': 'offline'})
              : row[2],
          row[0] == 'RECORDING_ASSET' && tombstone ? 1 : 0,
        ],
      );
    }
    await db.close();
    store = await manager.openAccount(owner);
  }

  test(
    'metadata acknowledgement is separate from pending pin and absent file',
    () async {
      await seed(cloud: 'QUEUED', reason: 'QUOTA');
      final s = await RecordingFileStatuses(store).read(id);
      expect(s.information, InformationSyncState.synced);
      expect(s.device, DeviceAudioState.missing);
      expect(s.serverStored, false);
      expect(s.pinLabel, '고정 대기');
      expect(s.waitingLabel, '대기 이유: 용량 부족');
    },
  );
  test('stored file alone cannot promote pending replacement; current pin is preserved', () async {
    await seed(cloud: 'STORED');
    expect((await RecordingFileStatuses(store).read(id)).pinLabel, '고정 대기');
    await seed(cloud: 'STORED', pending: false, current: true);
    final s = await RecordingFileStatuses(store).read(id);
    expect(s.pinLabel, '고정 보관 중');
    expect(s.device, DeviceAudioState.missing);
  });
  test('actual current-account file and offline draft are independent of cloud report', () async {
    await seed(cloud: 'NONE', draft: true, pending: false);
    await store.preserveDownloadedAudio(
      owner,
      id,
      sha256.convert(bytes).toString(),
      4,
      bytes,
    );
    final s = await RecordingFileStatuses(store).read(id);
    expect(s.device, DeviceAudioState.available);
    expect(s.information, InformationSyncState.pending);
    expect(s.serverStored, false);
  });
  test('newer deleted asset overrides old stored evidence; missing evidence stays unknown', () async {
    expect(
      (await RecordingFileStatuses(store).read(id)).serverState,
      'UNKNOWN',
    );
    await seed(cloud: 'STORED', current: true, pending: false, tombstone: true);
    final s = await RecordingFileStatuses(store).read(id);
    expect(s.serverState, 'NONE');
    expect(s.serverStored, false);
  });
  test(
    'incomplete STORED evidence cannot claim backup or pin completion',
    () async {
      await seed(cloud: 'STORED', pending: false, current: true, invalid: true);
      final status = await RecordingFileStatuses(store).read(id);
      expect(status.serverStored, false);
      expect(status.serverState, 'UNKNOWN');
      expect(status.pinLabel, '고정 상태 확인 중');
    },
  );
  testWidgets(
    'status card keeps four states separate without a backup-complete shortcut',
    (tester) async {
      const status = RecordingFileStatus(
        recording: 'synthetic',
        information: InformationSyncState.synced,
        device: DeviceAudioState.missing,
        serverState: 'QUEUED',
        blockedReason: 'QUOTA',
        pinCurrent: false,
        pinPending: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RecordingFileStatusCard(status: status)),
        ),
      );
      for (final text in [
        '정보 동기화 완료',
        '이 기기 파일: 재생 가능한 파일 없음',
        '서버 파일: 보관 대기',
        '대기 이유: 용량 부족',
        '고정 대기',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('파일 백업 완료'), findsNothing);
    },
  );
}
