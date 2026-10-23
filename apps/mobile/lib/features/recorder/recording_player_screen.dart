import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/audio/audio_player.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';

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
    appBar: appPageBar(context, title: const Text('녹음 재생')),
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
            padding: AppLayout.bodyPadding,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Text(
                  time(player.position),
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  time(player.duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (player.waveform.isNotEmpty)
                SizedBox(
                  height: 116,
                  child: CustomPaint(
                    painter: _Waveform(
                      player.waveform,
                      player.duration == 0
                          ? 0
                          : player.position / player.duration,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '5초 뒤로',
                      onPressed: seekable
                          ? () => unawaited(
                              player.seek(
                                (player.position - 5000).clamp(
                                  0,
                                  player.duration,
                                ),
                              ),
                            )
                          : null,
                      icon: const AppIcon(Icons.replay_5),
                    ),
                    FilledButton.icon(
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                        minimumSize: const Size(68, 68),
                      ),
                      icon: AppIcon(
                        playing ? Icons.pause : Icons.play_arrow,
                        size: 30,
                      ),
                      label: Text(playing ? '일시정지' : '재생'),
                      onPressed: () => unawaited(
                        playing
                            ? player.pause()
                            : player.phase == PlaybackPhase.paused
                            ? player.resume()
                            : player.start(widget.recordingId),
                      ),
                    ),
                    IconButton(
                      tooltip: '5초 앞으로',
                      onPressed: seekable
                          ? () => unawaited(
                              player.seek(
                                (player.position + 5000).clamp(
                                  0,
                                  player.duration,
                                ),
                              ),
                            )
                          : null,
                      icon: const AppIcon(Icons.forward_5),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _Waveform extends CustomPainter {
  _Waveform(this.peaks, this.progress, this.color);
  final List<double> peaks;
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final height = (peaks[i] * size.height).clamp(1.0, size.height);
      final paint = Paint()
        ..color = color.withValues(
          alpha: i / peaks.length <= progress ? 1 : .25,
        )
        ..strokeWidth = (step * .6).clamp(1.0, 3.0)
        ..strokeCap = StrokeCap.round;
      final x = (i + .5) * step;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Waveform oldDelegate) =>
      oldDelegate.peaks != peaks ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}
