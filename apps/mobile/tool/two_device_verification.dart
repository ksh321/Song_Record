import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/sync_controller.dart';
import 'package:song_record/features/sync/sync_screen.dart';

import 'sync_verification_fixture.dart';

/// Explicit debug entry only. Uses synthetic sessions from the loopback H2 harness.
class TwoDeviceVerificationScreen extends StatefulWidget {
  const TwoDeviceVerificationScreen({super.key});
  @override
  State<TwoDeviceVerificationScreen> createState() =>
      _TwoDeviceVerificationState();
}

class _TwoDeviceVerificationState extends State<TwoDeviceVerificationScreen> {
  static final base = Uri.parse('http://127.0.0.1:19090');
  AccountStoreManager? manager;
  AccountStore? store;
  LocalRepository? repo;
  AuthSession? auth;
  SyncController? controller;
  Directory? run;
  String role = '', rec = '', text = '역할을 선택하세요.';
  bool busy = false;
  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
      await summary();
    } catch (e) {
      if (mounted) setState(() => text = '실패: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect(String selected) async {
    controller?.dispose();
    await manager?.logout();
    final client = HttpClient();
    late Map<String, dynamic> config;
    try {
      final request = await client.getUrl(
        base.resolve('/verification/session/$selected'),
      );
      final response = await request.close();
      if (response.statusCode != 200) throw StateError('Harness unavailable');
      config = jsonDecode(
        await utf8.decoder.bind(response).join(),
      ) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/isolated-two-device-checks');
    await root.create(recursive: true);
    final identity = jsonEncode({
      'owner': config['owner'],
      'device': config['device'],
      'recording': config['recording'],
    });
    Directory? previous;
    await for (final entry in root.list()) {
      if (entry is! Directory ||
          !entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('device-$selected-')) {
        continue;
      }
      final marker = File('${entry.path}/identity.json');
      if (await marker.exists() && await marker.readAsString() == identity) {
        previous = entry;
        break;
      }
    }
    run = previous ?? await root.createTemp('device-$selected-');
    if (previous == null) {
      await File('${run!.path}/identity.json')
          .writeAsString(identity, flush: true);
    }
    role = selected;
    rec = config['recording'] as String;
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => run!,
      temporaryDirectory: () async => run!,
    );
    store = await manager!.openAccount(config['owner'] as String);
    repo = LocalRepository(store!);
    auth = AuthSession(
      userId: store!.userId,
      deviceId: config['device'] as String,
      accessToken: config['access'] as String,
      refreshToken: 'unused',
      accessExpiresAt: DateTime.utc(2099),
      refreshExpiresAt: DateTime.utc(2099),
    );
    if (previous == null) {
      await installVerificationSnapshot(
        store!,
        verificationSnapshot(
          owner: store!.userId,
          token: UuidValue.random().value,
          cursor: 0,
          now: DateTime.now(),
          rows: {},
        ),
      );
    }
    controller = SyncController(
      RepositorySyncBackend(
        repo!,
        HttpMutationTransport(base, allowLocalHttp: true),
        () async => auth!,
      ),
      conflicts: repo!,
    );
  }

  Future<void> send() async {
    await repo!.dispatch(
      transport: HttpMutationTransport(base, allowLocalHttp: true),
      session: () async => auth!,
    );
    await controller!.refresh();
  }

  Future<void> pull() async {
    final receiver = ChangeFeedReceiver(
      store: store!,
      transport: HttpChangeFeedTransport(base, allowLocalHttp: true),
      isSessionCurrent: (s) => identical(s, auth),
    );
    for (var i = 0; i < 20; i++) {
      final result = await receiver.step(auth!);
      if (result == ChangeFeedStep.caughtUp) return;
    }
    throw StateError('Receive did not finish');
  }

  Future<void> create() async {
    if (role != 'A') throw StateError('Use A');
    final draft = <String, Object?>{
      'metadata_state': 'DRAFT',
      'song_id': null,
      'title_snapshot': '두 기기 검증 녹음',
      'artist_snapshot': '합성 가수',
      'version_code': 'NORMAL',
      'key_mode': 'ORIGINAL',
      'key_shift': 0,
      'note': '처음 메모',
      'recorded_at': '2026-09-30T00:00:00Z',
      'timezone_id': 'UTC',
      'timezone_offset_minutes': 0,
    };
    final bytes = <int>[1, 3, 5, 7];
    final spec = <String, Object?>{
      'sha256': sha256.convert(bytes).toString(),
      'size_bytes': 4,
      'duration_ms': 1000,
      'codec': 'AAC_LC',
      'sample_rate': 48000,
      'channels': 1,
      'capture_integrity': 'VALIDATED',
    };
    await repo!.save(
      repo!.prepareCreate(
        entity: LocalEntity.recording,
        entityId: rec,
        draft: draft,
        changes: draft,
      ),
    );
    await repo!.save(
      repo!.preparePatch(
        entity: LocalEntity.recording,
        entityId: rec,
        baseRevision: 0,
        draft: {...draft, 'metadata_state': 'SAVED', 'file': spec},
        changes: {'metadata_state': 'SAVED', 'file': spec},
      ),
    );
    final paths = await AccountPaths.create(
      run!,
      store!.userId,
      AppEnvironment.dev,
    );
    await (await paths.checkedFile(paths.audioPath(rec)))
        .writeAsBytes(bytes, flush: true);
    await send();
  }

  Future<void> edit(
    Map<String, Object?> changes, {
    bool transmit = true,
  }) async {
    final copy = (await repo!.read(LocalEntity.recording, rec))!;
    await repo!.save(
      repo!.preparePatch(
        entity: LocalEntity.recording,
        entityId: rec,
        baseRevision: copy.revision,
        draft: {
          ...jsonDecode(copy.serverJson!) as Map<String, dynamic>,
          ...changes,
        },
        changes: changes,
      ),
    );
    if (transmit) await send();
  }

  Future<void> song() async {
    final id = UuidValue.random().value;
    final body = <String, Object?>{
      'source_type': 'TJ',
      'source_token': 'valid',
      'note': '$role 개인 메모',
    };
    await repo!.save(
      repo!.prepareCreate(
        entity: LocalEntity.song,
        entityId: id,
        draft: body,
        changes: body,
      ),
    );
    await send();
  }

  Future<void> summary() async {
    if (store == null) return;
    final copy = await repo!.read(LocalEntity.recording, rec);
    final value = copy?.serverJson == null
        ? <String, dynamic>{}
        : jsonDecode(copy!.serverJson!) as Map<String, dynamic>;
    final paths = await AccountPaths.create(
      run!,
      store!.userId,
      AppEnvironment.dev,
    );
    final file = await paths.checkedFile(paths.audioPath(rec));
    final pending = await repo!.pendingWork();
    final mappings = await repo!.canonicalCandidates();
    final report = <String, Object?>{
      'role': role,
      'revision': copy?.revision,
      'note': value['note'],
      'tier': value['tier'],
      'file_present': await file.exists(),
      'file_preserved': !await file.exists()
          ? null
          : sha256.convert(await file.readAsBytes()).toString() ==
                sha256.convert([1, 3, 5, 7]).toString(),
      'pending': pending
          .map(
            (m) => {
              'entity': m.entity.code,
              'state': m.state,
              'attempts': m.attemptCount,
            },
          )
          .toList(),
      'canonical_choices': mappings.length,
    };
    await File('${run!.path}/result.json')
        .writeAsString(jsonEncode(report), flush: true);
    if (mounted) {
      setState(
        () => text =
            '역할 $role · revision ${copy?.revision ?? 0}\n메모: ${value['note'] ?? '-'}\n티어: ${value['tier'] ?? '-'}\n녹음 파일: ${awaitFileLabel(report)}\n대기 ${pending.length} · 곡 선택 ${mappings.length}',
      );
    }
  }

  String awaitFileLabel(Map<String, Object?> report) =>
      report['file_present'] == true ? '이 기기에 보존' : '이 기기에는 없음';
  Future<void> review() async {
    await controller!.refresh();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('실제 서버 충돌 검토')),
          body: SyncScreen(controller: controller!),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    manager?.logout();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('두 기기 실제 통신 검증')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('일회용 합성 계정·DB. 폰=A, 에뮬레이터=B. 실제 녹음이나 운영 서버를 사용하지 않습니다.'),
        Text(text),
        for (final selected in ['A', 'B'])
          FilledButton(
            onPressed: busy ? null : () => action(() => connect(selected)),
            child: Text('$selected 연결'),
          ),
        if (store != null) ...[
          for (final entry in <String, Future<void> Function()>{
            'A 녹음 생성·저장': create,
            '서버 정보 받기': pull,
            'B 티어 A 저장': () => edit({'tier': 'A'}),
            '메모 오프라인 준비': () => edit({'note': '$role 새 메모'}, transmit: false),
            '준비한 변경 전송': send,
            '같은 TJ 곡 등록': song,
            '충돌·곡 선택 화면': review,
            '결과 새로고침': summary,
          }.entries)
            OutlinedButton(
              onPressed: busy ? null : () => action(entry.value),
              child: Text(entry.key),
            ),
        ],
      ],
    ),
  );
}
