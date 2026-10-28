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
    this.autoplay = true,
    this.title = '녹음 듣기',
    this.initialDuration = 0,
    this.onDetails,
    super.key,
  });
  final String recordingId;
  final bool autoplay;
  final String title;
  final int initialDuration;
  final VoidCallback? onDetails;
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
    if (widget.autoplay) unawaited(player.start(widget.recordingId));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String time(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}.${(milliseconds % 1000) ~/ 100}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(
      context,
      title: Text(
        widget.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, height: 1.5),
      ),
      showSettings: widget.onDetails == null,
      actions: [
        if (widget.onDetails != null)
          IconButton(
            tooltip: '녹음 상세 메뉴',
            icon: const AppIcon(Icons.more_vert),
            onPressed: () async {
              if (player.phase == PlaybackPhase.playing) await player.pause();
              if (mounted) widget.onDetails?.call();
            },
          ),
      ],
    ),
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
              const SizedBox(height: 40),
              Center(
                child: Text(
                  time(player.position),
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  time(
                    player.duration > 0
                        ? player.duration
                        : widget.initialDuration,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                height: 135,
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
              const SizedBox(height: 10),
              const Text('재생 위치', style: TextStyle(fontSize: 10)),
              Slider(
                semanticFormatterCallback: (v) => time(v.toInt()),
                value: player.position.clamp(0, player.duration).toDouble(),
                max: player.duration > 0 ? player.duration.toDouble() : 1,
                onChanged: seekable
                    ? (v) => unawaited(player.seek(v.toInt()))
                    : null,
              ),
              const SizedBox(height: 45),
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
                    IconButton.filled(
                      tooltip: playing ? '일시정지' : '재생',
                      style: IconButton.styleFrom(
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        minimumSize: const Size(76, 76),
                        shape: const CircleBorder(),
                      ),
                      icon: AppIcon(
                        playing ? Icons.pause : Icons.play_arrow,
                        size: 30,
                      ),
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
    if (peaks.isEmpty) return;
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
