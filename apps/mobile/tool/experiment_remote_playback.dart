// Read-only physical check: same installed package/session, no local source
// removal and no upload, account creation, refresh, or metadata mutation.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_http.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  if (!kDebugMode ||
      config.environment != AppEnvironment.staging ||
      config.apiBaseUrl.scheme != 'https') {
    throw StateError('Debug experiment only');
  }
  runApp(MaterialApp(theme: AppTheme.dark(), home: RemoteCheck(config)));
}

class RemoteCheck extends StatefulWidget {
  const RemoteCheck(this.config, {super.key});
  final AppConfig config;
  @override
  State<RemoteCheck> createState() => _RemoteCheckState();
}

class _RemoteCheckState extends State<RemoteCheck> with WidgetsBindingObserver {
  final player = AndroidAudioPlayer();
  late final StreamSubscription<PlayerEvent> events;
  AccountStoreManager? manager;
  AccountStore? store;
  String message = '기존 시험 녹음의 서버 사본만 재생합니다. 기기 원본은 유지합니다.';
  String? recording, checksum;
  int size = 0, position = 0, duration = 0, generation = 0;
  bool busy = false, current = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    events = player.events.listen(
      (event) {
        if (!mounted || !current || event.token != generation) return;
        setState(() {
          position = event.position;
          duration = event.duration;
        });
        if (event.phase == PlaybackPhase.completed) unawaited(finish());
        if (event.phase == PlaybackPhase.failed) {
          setState(() {
            message = '원격 재생 실패';
            busy = false;
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            message = '원격 재생 실패';
            busy = false;
          });
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      current = false;
      generation++;
      unawaited(player.stop());
    }
  }

  Future<void> start() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '기존 세션·원본·서버 보관 확인 중';
    });
    current = true;
    final token = ++generation;
    var stage = '세션';
    try {
      final config = widget.config;
      final vault = SecureSessionVault(
        '${config.environment.name}:${config.apiBaseUrl}',
      );
      final raw = await vault.read();
      if (raw == null) throw StateError('Session unavailable');
      final session = AuthSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      Future<void> guard() async {
        if (!mounted ||
            !current ||
            token != generation ||
            !session.accessExpiresAt.isAfter(DateTime.now().toUtc()) ||
            await vault.read() != raw) {
          throw StateError('Session changed');
        }
        store?.requireActive();
      }

      await guard();
      if (await HttpAuthApi(config.apiBaseUrl).me(session) != session.userId) {
        throw StateError('Owner changed');
      }
      await guard();
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': session.userId, 'environment': config.environment.name},
      );
      stage = '기기 원본';
      manager ??= AccountStoreManager(
        environment: config.environment,
        origin: config.apiBaseUrl,
      );
      store ??= await manager!.openAccount(session.userId);
      if (store!.userId != session.userId) throw StateError('Owner changed');
      final rows = (await LocalRepository(store!).recordingCatalog()).rows;
      if (rows.length != 1) {
        throw StateError('Exactly one experiment recording required');
      }
      final id = rows.single['id'] as String;
      final status = await RecordingFileStatuses(store!).read(id);
      if (!status.serverStored) throw StateError('Stored evidence required');
      final original = await store!.findPlayableLocalAudio(id);
      if (original == null) throw StateError('Preserved original required');
      recording = id;
      checksum = original.checksum;
      size = original.size;
      stage = '서버 재생 주소';
      final ticket = await HttpPlaybackUrls(config.apiBaseUrl, () async {
        await guard();
        return session;
      }).issue(id, guard);
      await guard();
      if (ticket.owner != session.userId ||
          ticket.recording != id ||
          ticket.checksum != checksum ||
          ticket.size != size ||
          !ticket.expiresAt.isAfter(DateTime.now().toUtc()) ||
          ticket.expiresAt.difference(DateTime.now().toUtc()) >
              const Duration(minutes: 5, seconds: 15)) {
        throw StateError('Ticket mismatch');
      }
      stage = '원격 음원';
      await player.stop();
      duration = await player.load({
        'token': token,
        'userId': session.userId,
        'environment': config.environment.name,
        'recordingId': id,
        'kind': 'remote',
        'url': ticket.url.toString(),
        'allowLocalHttp': false,
      });
      await guard();
      if (duration < 1) throw StateError('No audio');
      await player.play(token);
      await guard();
      if (mounted) setState(() => message = '서버 사본 재생 중');
    } catch (_) {
      await player.stop();
      if (mounted) {
        setState(() {
          message = '$stage 확인 실패 — 정식 앱에서 상태를 확인하세요.';
          busy = false;
        });
      }
    }
  }

  Future<void> finish() async {
    final original = await store!.findPlayableLocalAudio(recording!);
    final preserved = original?.checksum == checksum && original?.size == size;
    if (mounted && current) {
      setState(() {
        message = preserved && position >= 3000
            ? '서버 재생 완료 · 원본 보존 확인'
            : '재생 또는 원본 확인 필요';
        busy = false;
      });
    }
  }

  @override
  void dispose() {
    current = false;
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(events.cancel());
    unawaited(player.stop());
    unawaited(manager?.logout());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P25-06 서버 재생 확인')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(message),
          Text('${position ~/ 1000}초 / ${duration ~/ 1000}초'),
          FilledButton(
            onPressed: busy ? null : start,
            child: const Text('서버 시험 녹음 듣기'),
          ),
        ],
      ),
    ),
  );
}
