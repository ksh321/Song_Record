import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/uploads/upload_dispatcher.dart';
import 'package:song_record/core/uploads/upload_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

String uploadFixtureId(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

final class UploadFixtureTransport implements UploadTransport {
  UploadFixtureTransport(this.clock);
  final DateTime Function() clock;
  bool failNetwork = false;
  int approvalStatus = 201, putStatus = 200, putCount = 0;
  final order = <String>[];
  Future<void> Function()? beforeReply;
  @override
  Future<UploadResponse> authorize(
    UploadWork w,
    AuthSession session,
    UploadGuard guard,
  ) async {
    await guard();
    order.add(w.recordingId);
    await beforeReply?.call();
    if (failNetwork) throw const UploadNetworkFailure();
    return UploadResponse(
      approvalStatus,
      jsonEncode({
        'attempt_id': w.attemptId ?? uploadFixtureId(100 + order.length),
        'state': 'UPLOADING',
        'put_url':
            'https://${'a' * 32}.r2.cloudflarestorage.com/temporary/fixture',
        'headers': <String, Object>{},
        'expires_at': clock()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'attempt_expires_at': clock()
            .add(const Duration(hours: 24))
            .toIso8601String(),
      }),
    );
  }

  @override
  Future<UploadResponse> renew(UploadWork w, AuthSession s, UploadGuard g) =>
      authorize(w, s, g);
  @override
  Future<int> put(
    Uri url,
    Map<String, List<String>> headers,
    Uint8List bytes,
    UploadGuard guard,
  ) async {
    await guard();
    putCount++;
    return putStatus;
  }
}

final class UploadFixture {
  UploadFixture(this.root) {
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    transport = UploadFixtureTransport(() => now);
  }
  final Directory root;
  DateTime now = DateTime.utc(2026, 10, 8);
  late final AccountStoreManager manager;
  late AccountStore store;
  late final UploadFixtureTransport transport;
  final owner = uploadFixtureId(1);
  final bytes = Uint8List.fromList(utf8.encode('P12-05 synthetic original'));
  Future<void> open() async {
    await root.create(recursive: true);
    store = await manager.openAccount(owner);
  }

  Future<void> sql(String statement, List<Object?> values) async {
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    try {
      await db.verifyReady();
      await db.customStatement(statement, values);
    } finally {
      await db.close();
    }
  }

  Future<void> seed(int n, {bool saved = true, bool pinned = false}) async {
    final id = uploadFixtureId(n), hash = sha256.convert(bytes).toString();
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    await (await paths.checkedFile(paths.audioPath(id)))
        .writeAsBytes(bytes, flush: true);
    await store.recordFileAndJournal(
      recordingId: id,
      operationId: uploadFixtureId(n + 1000),
      state: FilePresence.saved,
      phase: JournalPhase.committed,
      pending: false,
      checksum: hash,
      sizeBytes: bytes.length,
      recovery: {'synthetic': true},
    );
    await sql(
      "INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,'RECORDING',?,1,?,?)",
      [
        owner,
        id,
        jsonEncode({
          'id': id,
          'revision': 1,
          'lifecycle_state': 'ACTIVE',
          'metadata_state': saved ? 'SAVED' : 'DRAFT',
          'file': {'sha256': hash, 'size_bytes': bytes.length},
        }),
        now.millisecondsSinceEpoch,
      ],
    );
    if (pinned) {
      await sql(
        "INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,'PIN_SLOT',?,1,?,?)",
        [
          owner,
          uploadFixtureId(n + 2000),
          jsonEncode({'pending_recording_id': id}),
          now.millisecondsSinceEpoch,
        ],
      );
    }
  }

  Future<AuthSession> session() async => AuthSession(
    userId: owner,
    deviceId: uploadFixtureId(2),
    accessToken: 'synthetic-only',
    refreshToken: 'unused',
    accessExpiresAt: DateTime.utc(2099),
    refreshExpiresAt: DateTime.utc(2099),
  );
  UploadDispatcher get dispatcher =>
      UploadDispatcher(store, transport, session, clock: () => now);
  Future<bool> preserved(int n) async {
    final id = uploadFixtureId(n);
    final audio = await store.readLocalAudio(id);
    final meta = await store.readMetadata(LocalEntity.recording, id);
    return sha256.convert(audio).toString() ==
            sha256.convert(bytes).toString() &&
        meta?.serverJson != null;
  }

  Future<void> reopen() async {
    await manager.logout();
    store = await manager.openAccount(owner);
  }
}

Future<Map<String, bool>> verifyUploadQueue(Directory root) async {
  await root.create(recursive: true);
  final result = <String, bool>{};
  Future<void> scenario(
    String name,
    Future<bool> Function(UploadFixture) run,
  ) async {
    final fixture = UploadFixture(await root.createTemp('upload-'));
    try {
      await fixture.open();
      result[name] = await run(fixture);
    } finally {
      await fixture.manager.logout();
    }
  }

  await scenario('정보 승인 전 파일 전송 안 함', (f) async {
    await f.seed(10, saved: false);
    await f.dispatcher.dispatch();
    return f.transport.order.isEmpty && await f.preserved(10);
  });
  await scenario('고정·교체 우선 후 일반 전송', (f) async {
    await f.seed(10);
    await f.seed(11, pinned: true);
    await f.dispatcher.dispatch();
    return f.transport.order.join(',') ==
        '${uploadFixtureId(11)},${uploadFixtureId(10)}';
  });
  await scenario('네트워크 실패 1·5·15분, 자동 재시도 3회 제한', (f) async {
    await f.seed(10);
    f.transport.failNetwork = true;
    await f.dispatcher.dispatch();
    for (final minutes in [1, 5, 15]) {
      final due = await f.store.nextUploadAt();
      if (due != f.now.add(Duration(minutes: minutes))) return false;
      await f.dispatcher.dispatch();
      f.now = due!;
      await f.dispatcher.dispatch();
    }
    await f.reopen();
    return (await f.store.nextUploadAt()) == null &&
        f.transport.order.length == 4 &&
        await f.preserved(10);
  });
  await scenario('전송 중 취소 후 원본·정보 유지', (f) async {
    await f.seed(10);
    f.transport.beforeReply = () => f.store.cancelUpload(uploadFixtureId(10));
    await f.dispatcher.dispatch();
    await f.reopen();
    return f.transport.putCount == 0 &&
        (await f.store.uploadStatus()).single['phase'] == 'CANCELLED' &&
        await f.preserved(10);
  });
  await scenario('인증 만료 중단·직접 재시도 후 보존', (f) async {
    await f.seed(10);
    f.transport.approvalStatus = 401;
    var blocked = false;
    await f.dispatcher.dispatch(onAuthenticationBlocked: () => blocked = true);
    await f.dispatcher.dispatch();
    if (f.transport.order.length != 1 || !blocked) return false;
    await f.store.retryUpload(uploadFixtureId(10));
    f.transport.approvalStatus = 201;
    await f.dispatcher.dispatch();
    return f.transport.putCount == 1 && await f.preserved(10);
  });
  await scenario('계정 변경 후 늦은 응답 전송 차단', (f) async {
    await f.seed(10);
    f.transport.beforeReply = () async {
      await f.manager.openAccount(uploadFixtureId(99));
    };
    try {
      await f.dispatcher.dispatch();
      return false;
    } on StateError {
      /* expired account lease */
    }
    await f.reopen();
    return f.transport.putCount == 0 &&
        (await f.store.nextUploadAt()) == null &&
        await f.preserved(10);
  });
  await scenario('PUT 성공은 업로드 대기, 서버 보관 완료 아님', (f) async {
    await f.seed(10);
    await f.dispatcher.dispatch();
    await f.reopen();
    await f.dispatcher.dispatch();
    return f.transport.putCount == 1 &&
        (await f.store.uploadStatus()).single['phase'] == 'UPLOADED' &&
        await f.preserved(10);
  });
  return result;
}
