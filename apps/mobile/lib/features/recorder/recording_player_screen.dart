import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_player.dart';
import '../../core/theme/app_tokens.dart';

/// Owns only the visible player lifetime; source choice stays in AudioPlayback.
class RecordingPlayerScreen extends StatefulWidget {
  const RecordingPlayerScreen({
    required this.recordingId,
    required this.createPlayer,
    super.key,
  });
  final String recordingId;
  final AudioPlayback Function() createPlayer;

  @override
  State<RecordingPlayerScreen> createState() => _RecordingPlayerScreenState();
}

class _RecordingPlayerScreenState extends State<RecordingPlayerScreen> {
  late final AudioPlayback player;

  @override
  void initState() {
    super.initState();
    player = widget.createPlayer();
    unawaited(player.start(widget.recordingId));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String time(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('녹음 재생')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final playing = player.phase == PlaybackPhase.playing;
          final seekable = {
            PlaybackPhase.playing,
            PlaybackPhase.paused,
            PlaybackPhase.completed,
          }.contains(player.phase);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('${time(player.position)} / ${time(player.duration)}'),
              Slider(
                semanticFormatterCallback: (v) => time(v.toInt()),
                value: player.position.clamp(0, player.duration).toDouble(),
                max: player.duration > 0 ? player.duration.toDouble() : 1,
                onChanged: seekable
                    ? (v) => unawaited(player.seek(v.toInt()))
                    : null,
              ),
              if (player.phase == PlaybackPhase.loading)
                const Center(child: CircularProgressIndicator())
              else if (player.phase == PlaybackPhase.failed ||
                  player.phase == PlaybackPhase.unavailable) ...[
                const Text('녹음을 재생하지 못했어요. 파일과 인터넷 연결을 확인해 주세요.'),
                OutlinedButton(
                  onPressed: () => unawaited(player.start(widget.recordingId)),
                  child: const Text('다시 시도'),
                ),
              ] else
                FilledButton.icon(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: Text(playing ? '일시정지' : '재생'),
                  onPressed: () => unawaited(
                    playing
                        ? player.pause()
                        : player.phase == PlaybackPhase.paused
                        ? player.resume()
                        : player.start(widget.recordingId),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
