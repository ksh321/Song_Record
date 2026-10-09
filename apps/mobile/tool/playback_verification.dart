import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_http.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'local_preservation_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const PlaybackCheck()));
}

class CountingUrls implements PlaybackUrlProvider {
  CountingUrls(this.inner, this.reset);
  final PlaybackUrlProvider inner;
  final VoidCallback reset;
  int calls = 0;
  @override
  Future<PlaybackTicket> issue(String id, Future<void> Function() guard) async {
    calls++;
    reset();
    return inner.issue(id, guard);
  }
}

class PlaybackCheck extends StatefulWidget {
  const PlaybackCheck({super.key});
  @override
  State<PlaybackCheck> createState() => _State();
}

class _State extends State<PlaybackCheck> {
  final owner = preservationId(0x1401),
      local = preservationId(0x1402),
      remote = preservationId(0x1403),
      bad = preservationId(0x1404);
  AccountStoreManager? manager;
  AccountStore? store;
  AudioPlayback? flow;
  CountingUrls? urls;
  DateTime? simulated;
  String status = '준비 중';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final root = await getApplicationSupportDirectory();
      manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
      );
      store = await manager!.openAccount(owner);
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final data = await rootBundle.load(
        'assets/verification/playback-tone.m4a',
      );
      for (final entry in {
        local: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        bad: Uint8List.fromList([1, 2, 3, 4, 5]),
      }.entries) {
        final file = await paths.checkedFile(paths.audioPath(entry.key));
        if (!await file.exists()) {
          await file.writeAsBytes(entry.value, flush: true);
        }
        await store!.recordFileAndJournal(
          recordingId: entry.key,
          operationId: preservationId(entry.key == local ? 0x1412 : 0x1414),
          state: FilePresence.inputPending,
          phase: JournalPhase.verified,
          pending: false,
          checksum: sha256.convert(entry.value).toString(),
          sizeBytes: entry.value.length,
          recovery: {'note': 'P14-03 합성 입력 대기 원본'},
        );
      }
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': owner, 'environment': 'dev'},
      );
      urls = CountingUrls(
        HttpPlaybackUrls(
          Uri.parse('http://127.0.0.1:46414'),
          () async => AuthSession(
            userId: owner,
            deviceId: preservationId(0x1405),
            accessToken: 'synthetic-playback',
            refreshToken: 'synthetic',
            accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
            refreshExpiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          allowLocalHttp: true,
        ),
        () => simulated = null,
      );
      flow = AudioPlayback(
        store!,
        urls!,
        AndroidAudioPlayer(),
        clock: () => simulated ?? DateTime.now(),
      );
      flow!.addListener(update);
      status = '준비 완료 — 합성 12초 음. 개인 녹음 사용 안 함';
      update();
    } catch (_) {
      status = '준비 실패 — 이 문구를 알려 주세요';
      update();
    }
  }

  void update() {
    if (mounted) setState(() {});
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    update();
    try {
      await work();
    } catch (_) {
      status = '검사 실패';
    } finally {
      busy = false;
      update();
    }
  }

  Future<void> failure() async {
    final before = await store!.readJournal(bad);
    final bytes = await store!.readLocalAudio(bad);
    await flow!.start(bad);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await store!.readLocalAudio(bad);
    status =
        flow!.phase == PlaybackPhase.failed &&
            before == await store!.readJournal(bad) &&
            sha256.convert(bytes) == sha256.convert(after)
        ? '실패 후 입력·파일 보존 통과'
        : '실패 보존 검사 실패';
  }

  @override
  void dispose() {
    flow?.removeListener(update);
    flow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = flow;
    return Scaffold(
      appBar: AppBar(title: const Text('P14-03 실제 재생 검증')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(status),
            const SizedBox(height: 12),
            Text(
              '재생 상태: ${p?.phase.name ?? "준비"} / URL 발급 ${urls?.calls ?? 0}회',
            ),
            Text(
              '${((p?.position ?? 0) / 1000).toStringAsFixed(1)} / ${((p?.duration ?? 0) / 1000).toStringAsFixed(1)}초',
            ),
            Slider(
              value: (p?.position ?? 0).clamp(0, p?.duration ?? 0).toDouble(),
              max: (p?.duration ?? 0) > 0 ? p!.duration.toDouble() : 1,
              onChanged: p == null || busy
                  ? null
                  : (v) => action(() => p.seek(v.toInt())),
            ),
            FilledButton(
              onPressed: p == null || busy
                  ? null
                  : () => action(() => p.start(local)),
              child: const Text('1. 로컬 재생 (비행기 모드 가능)'),
            ),
            FilledButton(
              onPressed: p == null || busy
                  ? null
                  : () => action(() => p.start(remote)),
              child: const Text('2. 실제 R2 서버 재생 (네트워크 켜기)'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: p == null || busy ? null : () => action(p.pause),
                    child: const Text('일시정지'),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: p == null || busy
                        ? null
                        : () => action(p.resume),
                    child: const Text('다시 재생'),
                  ),
                ),
              ],
            ),
            FilledButton(
              onPressed: p == null || busy
                  ? null
                  : () => action(() async {
                      await p.pause();
                      simulated = DateTime.now().add(
                        const Duration(minutes: 6),
                      );
                      await p.resume();
                    }),
              child: const Text('3. 만료 시각 모의 → 실제 URL 재발급'),
            ),
            FilledButton(
              onPressed: p == null || busy ? null : () => action(failure),
              child: const Text('4. 실패 후 입력·파일 보존'),
            ),
            const Text(
              '1: 음 확인 → 정지 → 다시 재생 → 슬라이더 이동 → completed.\n2: 실제 R2 음 확인 → completed. USB는 유지.\n3: 서버 재생 중 눌러 URL 발급 수 증가·이어 재생 확인. 실제 5분 대기를 시각 모의로 단축합니다.\n4: 실패 후 입력·파일 보존 통과 확인. 네 항목 결과를 알려 주세요.',
            ),
          ],
        ),
      ),
    );
  }
}
