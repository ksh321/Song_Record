// P04-09 manual device probe. This is a separate debug/dev entry point.
// Run: flutter run --flavor dev -t tool/verify_account_storage_android.dart
// Once SEEDED is displayed, adb force-stop the dev app and launch it again.
// A second Dart isolate/hot restart in the same Android PID cannot pass.
// Fixtures live under a dedicated support-directory child, never the normal DB.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart'
    show AccountDatabase;
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';

String _id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  // Keep the manager alive after SEEDED. Force-stop must interrupt an open DB.
  final _probe = _StorageProbe();
  late final Future<String> _result;

  @override
  void initState() {
    super.initState();
    _result = _probe.run();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('P04-09 로컬 DB 검증')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final text = snapshot.hasError
                ? 'FAIL\n${snapshot.error}'
                : snapshot.data!;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(text),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                    },
                    child: const Text('결과 복사'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _StorageProbe {
  final _lines = <String>[];
  late Directory _base;
  late Directory _runDirectory;
  late AccountStoreManager _manager;
  late String _runId;

  void _log(String message) {
    _lines.add(message);
    debugPrint('[P04-09] $message');
  }

  void _check(bool condition, String label) {
    if (!condition) {
      throw StateError(label);
    }
    _log('PASS: $label');
  }

  void _json(String? actual, Map<String, Object?> expected, String label) {
    _check(
      actual != null &&
          canonicalJson(jsonDecode(actual) as Map<String, Object?>) ==
              canonicalJson(expected),
      label,
    );
  }

  Future<Directory> _child(Directory parent, String name) async {
    final location = p.join(parent.path, name);
    final type = await FileSystemEntity.type(location, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('Probe directory must not be a link or a file');
    }
    final directory = Directory(location);
    await directory.create();
    if (!p.equals(await directory.resolveSymbolicLinks(), location)) {
      throw StateError('Probe directory was redirected');
    }
    return directory;
  }

  Future<void> _writeJson(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.$pid.tmp');
    await temporary.writeAsString(canonicalJson(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<String> run() async {
    if (!kDebugMode ||
        !Platform.isAndroid ||
        appFlavor != 'dev' ||
        AppEnvironment.fromDefine() != AppEnvironment.dev) {
      throw StateError(
        'Use an Android DEBUG build with --flavor dev and APP_ENV=dev',
      );
    }
    final support = await getApplicationSupportDirectory();
    final canonicalSupport = Directory(await support.resolveSymbolicLinks());
    _base = await _child(canonicalSupport, 'p04_09_storage_verification');
    final markerFile = File(p.join(_base.path, 'active.json'));
    final markerType = await FileSystemEntity.type(
      markerFile.path,
      followLinks: false,
    );
    if (markerType != FileSystemEntityType.file &&
        markerType != FileSystemEntityType.notFound) {
      throw StateError('Probe marker must be a regular file');
    }
    _log('Android PID: $pid');
    Map<String, Object?>? marker;
    if (markerType == FileSystemEntityType.file) {
      marker =
          jsonDecode(await markerFile.readAsString()) as Map<String, Object?>;
      final run = marker['run_id'];
      if (marker['format'] != 1 ||
          run is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(run) ||
          marker['seed_pid'] is! int) {
        throw StateError(
          'Invalid probe marker; do not reset existing data automatically',
        );
      }
      _runId = run;
      if (marker['seed_pid'] == pid) {
        return 'WAITING FOR FORCE-STOP\n\n저장한 앱 프로세스가 아직 실행 중입니다.\n'
            'Hot Restart는 이 검증에 포함되지 않습니다.\nPID: $pid';
      }
      if (!await Directory(p.join(_base.path, _runId)).exists()) {
        throw StateError('Seeded test directory is missing');
      }
    } else {
      final random = Random.secure();
      _runId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      if (await FileSystemEntity.type(
            p.join(_base.path, _runId),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('Test run identifier already exists');
      }
    }
    _runDirectory = await _child(_base, _runId);
    _manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => _runDirectory,
      temporaryDirectory: () async => _runDirectory,
    );
    _log('Run: $_runId');
    try {
      if (marker == null) {
        await _seed();
        await _writeJson(markerFile, {
          'format': 1,
          'run_id': _runId,
          'seed_pid': pid,
          'seeded_at': DateTime.now().toUtc().toIso8601String(),
        });
        _log('SEEDED: 계정 A/B 데이터 저장 완료');
        _log('1/2 완료. 앱을 강제 종료한 뒤 같은 앱을 다시 실행하세요.');
        _log('DB 연결은 열린 상태입니다.');
      } else {
        _check(marker['seed_pid'] != pid, '다른 Android 프로세스에서 재실행');
        _log('Seed PID: ${marker['seed_pid']} -> Verify PID: $pid');
        await _verify();
        _log('ANDROID STORAGE RESTART: PASS');
        _log('합성 파일의 보존 검사이며 실제 녹음·재생 검사는 아닙니다.');
      }
      await _writeJson(File(p.join(_base.path, 'last_result.json')), {
        'format': 1,
        'run_id': _runId,
        'phase': marker == null ? 'SEEDED' : 'PASS',
        'seed_pid': marker?['seed_pid'] ?? pid,
        'verify_pid': marker == null ? null : pid,
        'checked_at': DateTime.now().toUtc().toIso8601String(),
        'checks': _lines,
        'local_schema_upgrade': 'NOT_RUN_ONLY_V1_EXISTS',
      });
      return _lines.join('\n');
    } catch (error) {
      _log('ANDROID STORAGE RESTART: FAIL');
      _log(error.toString());
      await _writeJson(File(p.join(_base.path, 'last_result.json')), {
        'format': 1,
        'run_id': _runId,
        'phase': 'FAIL',
        'pid': pid,
        'checks': _lines,
      });
      rethrow;
    }
  }

  Map<String, Object?> _draft(String owner, {bool latest = false}) => {
    'user_id': owner,
    'run_id': _runId,
    'title': owner == _id(1) ? '계정 A의 곡' : '계정 B의 곡',
    'edit': latest ? 'latest' : 'initial',
  };

  Map<String, Object?> _server() => {'title': '합성 서버 응답', 'run_id': _runId};

  Map<String, Object?> _recovery(String owner, {bool latest = false}) => {
    'run_id': _runId,
    'owner': owner,
    'stage': latest ? 'latest' : 'initial',
  };

  Map<String, Object?> _resume(String owner, {bool latest = false}) => {
    'snapshot_id': _id(300),
    'entity': 'SONG',
    'ordinal': latest ? 7 : 3,
    'owner': owner,
    'run_id': _runId,
  };

  List<int> _bytes(String owner) => utf8.encode(
    'P04-09 synthetic bytes; not playable audio; $_runId; $owner',
  );

  LocalEdit _edit(String owner, {bool latest = false}) => LocalEdit(
    opId: _id(latest ? 101 : 100),
    entity: LocalEntity.song,
    entityId: _id(10),
    operation: latest ? LocalOperation.patch : LocalOperation.create,
    baseRevision: latest ? 1 : 0,
    draft: _draft(owner, latest: latest),
    changes: _draft(owner, latest: latest),
  );

  Future<AccountPaths> _paths(String owner) =>
      AccountPaths.create(_runDirectory, owner, AppEnvironment.dev);

  Future<void> _journal(AccountStore store, {bool latest = false}) async {
    final bytes = _bytes(store.userId);
    await store.recordFileAndJournal(
      recordingId: _id(20),
      operationId: _id(21),
      state: FilePresence.saved,
      phase: JournalPhase.committed,
      pending: false,
      checksum: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      recovery: _recovery(store.userId, latest: latest),
    );
  }

  Future<void> _seedAccount(AccountStore store) async {
    _check(
      await store.readMetadata(LocalEntity.song, _id(10)) == null,
      '${store.userId}: 빈 DB 생성',
    );
    final paths = await _paths(store.userId);
    final file = await paths.checkedFile(paths.audioPath(_id(20)));
    await file.writeAsBytes(_bytes(store.userId), flush: true);
    await store.saveEdit(_edit(store.userId));
    await _journal(store);
    await store.createImportJob(
      jobId: _id(200),
      sourceUserId: store.userId,
      manifestHash: sha256.convert(_bytes(store.userId)).toString(),
      resourceIds: [_id(10), _id(20)],
    );
    await store.saveSnapshotResume(_resume(store.userId));
  }

  Future<void> _raw(
    String owner,
    Future<void> Function(AccountDatabase) action,
  ) async {
    final database = AccountDatabase(
      NativeDatabase(await (await _paths(owner)).databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    try {
      await database.verifyReady();
      await action(database);
    } finally {
      await database.close();
    }
  }

  Future<void> _seed() async {
    await _seedAccount(await _manager.openAccount(_id(1)));
    await _seedAccount(await _manager.openAccount(_id(2)));
    await _manager.logout();
    // Fixture-only SQL: sync/import writers are not connected to the app yet.
    await _raw(_id(1), (db) async {
      await db.transaction(() async {
        await db.customStatement(
          'UPDATE metadata_copies SET server_revision=1,server_payload=? '
          'WHERE entity_type=? AND entity_id=?',
          [canonicalJson(_server()), 'SONG', _id(10)],
        );
        await db.customStatement(
          "UPDATE local_mutations SET queue_state='CONFLICT',attempt_count=2,server_response=? WHERE op_id=?",
          [
            canonicalJson({'revision': 1, ..._server()}),
            _id(100),
          ],
        );
        await db.customStatement(
          'UPDATE sync_cursors SET last_change_seq=42,baseline_complete=1 WHERE singleton=1',
        );
        await db.customStatement(
          "UPDATE import_items SET status='APPLIED',result_payload='{}' WHERE import_job_id=? AND ordinal=1",
          [_id(200)],
        );
        await db.customStatement(
          "UPDATE import_jobs SET status='PAUSED',completed_items=1 WHERE import_job_id=?",
          [_id(200)],
        );
      });
    });
    final a = await _manager.openAccount(_id(1));
    // These final committed writes remain on an OPEN background DB connection.
    await a.saveEdit(_edit(a.userId, latest: true));
    await _journal(a, latest: true);
    await a.saveSnapshotResume(_resume(a.userId, latest: true));
  }

  Future<void> _verifyAccount(
    AccountStore store,
    String label, {
    required bool latest,
  }) async {
    final metadata = await store.readMetadata(LocalEntity.song, _id(10));
    _json(
      metadata?.localJson,
      _draft(store.userId, latest: latest),
      '$label 초안 보존',
    );
    _check(
      metadata?.revision == (latest ? 1 : 0) && metadata?.tombstone == false,
      '$label 서버 리비전·상태 보존',
    );
    if (latest) {
      _json(metadata?.serverJson, _server(), '$label 서버 사본 보존');
    }
    final mutations = await store.pendingMutations();
    _check(mutations.length == (latest ? 2 : 1), '$label 전송 대기 개수 보존');
    final original = mutations.singleWhere((item) => item.opId == _id(100));
    _json(original.payload, _draft(store.userId), '$label 원래 요청 본문 보존');
    _check(
      original.baseRevision == 0 && original.basePayload == null,
      '$label 원래 기준 리비전 보존',
    );
    _check(
      original.state == (latest ? 'CONFLICT' : 'PENDING') &&
          original.attemptCount == (latest ? 2 : 0),
      '$label 대기·충돌·재시도 상태 보존',
    );
    if (latest) {
      _json(original.serverResponse, {
        'revision': 1,
        ..._server(),
      }, '$label 충돌 응답 보존');
      final newer = mutations.singleWhere((item) => item.opId == _id(101));
      _json(
        newer.payload,
        _draft(store.userId, latest: true),
        '$label 최신 요청 보존',
      );
      _json(newer.basePayload, _server(), '$label 최신 요청의 기준 사본 보존');
      _check(
        newer.state == 'PENDING' &&
            newer.baseRevision == 1 &&
            newer.attemptCount == 0,
        '$label 최신 요청 상태 보존',
      );
    }
    _check(
      listEquals(await store.readLocalAudio(_id(20)), _bytes(store.userId)),
      '$label 합성 파일 내용·크기·해시 보존',
    );
    _json(
      await store.readJournal(_id(20)),
      _recovery(store.userId, latest: latest),
      '$label 녹음 journal 보존',
    );
    _json(
      await store.readSnapshotResume(),
      _resume(store.userId, latest: latest),
      '$label snapshot 재개 정보 보존',
    );
    _check(
      await store.readCursor() == (latest ? 42 : null),
      '$label 동기화 cursor 보존',
    );
    _check(
      listEquals(await store.pendingImportJobs(), [_id(200)]),
      '$label 가져오기 대기 보존',
    );
  }

  Future<void> _verify() async {
    for (final user in [_id(1), _id(2)]) {
      final file = await (await _paths(user)).databaseFile();
      _check(
        await file.exists() && await file.length() > 0,
        '$user 기존 DB 파일 존재',
      );
    }
    final a = await _manager.openAccount(_id(1));
    await _verifyAccount(a, 'A', latest: true);
    final b = await _manager.openAccount(_id(2));
    var expired = false;
    try {
      await a.readCursor();
    } on StateError catch (error) {
      expired = error.message == 'This account storage session has expired';
    }
    _check(expired, '계정 전환 뒤 이전 세션 거절');
    await _verifyAccount(b, 'B', latest: false);
    final reopenedA = await _manager.openAccount(_id(1));
    _json(
      (await reopenedA.readMetadata(LocalEntity.song, _id(10)))?.localJson,
      _draft(_id(1), latest: true),
      'B에서 A로 돌아와도 같은 UUID의 데이터 분리',
    );
    await _manager.logout();
    await _raw(_id(1), (db) async {
      final job = await db
          .customSelect(
            'SELECT status,completed_items,total_items FROM import_jobs',
          )
          .getSingle();
      _check(
        job.read<String>('status') == 'PAUSED' &&
            job.read<int>('completed_items') == 1 &&
            job.read<int>('total_items') == 2,
        '가져오기 부분 진행 1/2 보존',
      );
      final items = await db
          .customSelect('SELECT status FROM import_items ORDER BY ordinal')
          .get();
      _check(
        listEquals(items.map((row) => row.read<String>('status')).toList(), [
          'APPLIED',
          'PENDING',
        ]),
        '가져오기 항목별 진행 보존',
      );
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      _check(version.read<int>('user_version') == 1, '로컬 스키마 v1 유지');
    });
  }
}
