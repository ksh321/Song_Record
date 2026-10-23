// Isolated synthetic playback check. No login, network, microphone, or user data.
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/files/recording_download.dart';

const owner = 'eeeeeeee-eeee-4eee-8eee-eeeeeeee2504';
const recording = 'eeeeeeee-eeee-4eee-8eee-eeeeeeee3401';

class FixtureDownload implements SignedAudioDownload {
  FixtureDownload(this.bytes);
  final Uint8List bytes;
  int calls = 0;
  @override
  Future<Uint8List> fetch(
    PlaybackTicket ticket,
    Future<void> Function() guard,
  ) async {
    calls++;
    await guard();
    return bytes;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) throw StateError('Verification only');
  runApp(const MaterialApp(home: VerifyWaveform()));
}

class VerifyWaveform extends StatefulWidget {
  const VerifyWaveform({super.key});
  @override
  State<VerifyWaveform> createState() => _State();
}

class _State extends State<VerifyWaveform> {
  String result = '합성 음원 파형 검사 중';
  @override
  void initState() {
    super.initState();
    unawaited(check());
  }

  Future<void> check() async {
    StreamSubscription<PlayerEvent>? subscription;
    AndroidAudioPlayer? player;
    var stage = 'fixture';
    try {
      final asset = await rootBundle.load(
        'assets/verification/playback-tone.m4a',
      );
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final checksum = sha256.convert(bytes).toString();
      final root = await getApplicationSupportDirectory();
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final file = await paths.checkedFile(paths.audioPath(recording));
      if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await file.readAsBytes()).toString() != checksum) {
        throw StateError('Existing fixture mismatch');
      }
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': owner, 'environment': 'dev'},
      );
      final download = FixtureDownload(bytes);
      player = AndroidAudioPlayer(download: download);
      final events = <PlayerEvent>[];
      subscription = player.events.listen(events.add);
      final ticket = PlaybackTicket(
        owner: owner,
        recording: recording,
        generation: 'eeeeeeee-eeee-4eee-8eee-eeeeeeee3402',
        checksum: checksum,
        size: bytes.length,
        revision: 1,
        url: Uri.parse('https://fixture.r2.cloudflarestorage.com/synthetic'),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      Future<PlayerEvent> waitFor(
        int token,
        bool Function(PlayerEvent) predicate,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(deadline)) {
          final matching = events.where(
            (e) => e.token == token && predicate(e),
          );
          if (matching.isNotEmpty) return matching.last;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        throw StateError('Playback observation timed out');
      }

      stage = 'memory waveform';
      await player.load({
        'token': 1,
        'kind': 'remote',
        'ticket': ticket,
        'userId': owner,
        'environment': 'dev',
        'recordingId': recording,
      });
      final memory = await waitFor(
        1,
        (e) => e.waveform.length == 120 && e.duration > 0,
      );
      if (!memory.waveform.any((v) => v > 0) || download.calls != 1) {
        throw StateError('No real waveform');
      }
      await player.play(1);
      await waitFor(
        1,
        (e) => e.phase == PlaybackPhase.playing && e.position > 0,
      );
      await player.pause(1);
      await player.seek(1, memory.duration ~/ 2);
      await waitFor(
        1,
        (e) =>
            e.phase == PlaybackPhase.paused &&
            e.position >= memory.duration ~/ 2 - 100,
      );
      stage = 'local waveform parity';
      await player.stop();
      await player.load({
        'token': 2,
        'kind': 'local',
        'path': file.path,
        'size': bytes.length,
        'sha256': checksum,
        'userId': owner,
        'environment': 'dev',
        'recordingId': recording,
      });
      final local = await waitFor(
        2,
        (e) => e.waveform.length == 120 && e.duration > 0,
      );
      stage = 'waveform comparison';
      if (!listEquals(local.waveform, memory.waveform)) {
        throw StateError('Waveform differs');
      }
      if (sha256.convert(await file.readAsBytes()).toString() != checksum) {
        throw StateError('Fixture changed');
      }
      if (mounted) {
        setState(
          () => result =
              'PASS · 실제 120개 파형\n메모리/로컬 일치 · 재생/일시정지/탐색\n수신 1회 · 원본 보존',
        );
      }
    } catch (error) {
      final code = error is PlatformException
          ? error.code
          : error.runtimeType.toString();
      if (mounted) setState(() => result = 'FAIL · $stage · $code');
    } finally {
      await player?.stop();
      await subscription?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(child: Text(result, textAlign: TextAlign.center)),
    ),
  );
}
