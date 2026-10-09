import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_http.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/recording_download.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'local_preservation_fixture.dart';
import 'playback_verification.dart' show CountingUrls;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const DownloadCheck()));
}

class DownloadCheck extends StatefulWidget {
  const DownloadCheck({super.key});
  @override
  State<DownloadCheck> createState() => _State();
}

class _State extends State<DownloadCheck> {
  String result = '검사 중';
  @override
  void initState() {
    super.initState();
    run();
  }

  Future<void> run() async {
    final owner = preservationId(0x1401), id = preservationId(0x1403);
    final manager = AccountStoreManager(environment: AppEnvironment.dev);
    AudioPlayback? player;
    try {
      final store = await manager.openAccount(owner);
      final before = await store.readMetadata(LocalEntity.recording, id);
      final urls = CountingUrls(
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
        () {},
      );
      final source = await RecordingDownload(store, urls).download(id);
      final audio = await store.readLocalAudio(id);

      if (source.size != audio.length ||
          before != await store.readMetadata(LocalEntity.recording, id) ||
          before != null ||
          await store.readJournal(id) != null) {
        throw StateError('Identity changed');
      }
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': owner, 'environment': 'dev'},
      );
      player = AudioPlayback(
        store,
        HttpPlaybackUrls(
          Uri.parse('http://127.0.0.1:1'),
          () async => throw StateError('Offline must not request URL'),
          allowLocalHttp: true,
        ),
        AndroidAudioPlayer(),
      );
      await player.start(id);
      if (player.phase != PlaybackPhase.playing) {
        throw StateError('Local playback failed');
      }
      await player.pause();
      result =
          'P14-04 ${urls.calls == 1 ? "실제 R2 다운로드" : "기존 계정 사본 재사용"}·계정 영속 파일·같은 UUID·메타정보 미생성·오프라인 native 재생 5개 통과';
    } catch (_) {
      result = 'P14-04 검사 실패';
    } finally {
      player?.dispose();
      await manager.logout();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P14-04 파일 다운로드 검증')),
    body: Padding(padding: const EdgeInsets.all(20), child: Text(result)),
  );
}
