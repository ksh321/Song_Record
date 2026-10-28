import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

class _RecordingPlayerScreenState extends State<RecordingPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AudioPlayback player;
  late final Ticker motion;
  final positionClock = Stopwatch();
  int? scrubPosition;

  // Native position reports arrive every 500ms. Interpolate only that interval;
  // stale events must not make a stalled player appear to keep playing.
  int get visiblePosition =>
      (player.position +
              (player.phase == PlaybackPhase.playing
                  ? positionClock.elapsedMilliseconds.clamp(0, 500)
                  : 0))
          .clamp(0, player.duration);

  void syncMotion() {
    positionClock.reset();
    if (player.phase == PlaybackPhase.playing) {
      positionClock.start();
      if (!motion.isActive) motion.start();
    } else {
      positionClock.stop();
      motion.stop();
    }
  }

  double scrubOriginX = 0;
  int scrubOriginPosition = 0;

  @override
  void initState() {
    super.initState();
    player = widget.createPlayer();
    motion = createTicker((_) {
      if (mounted && scrubPosition == null) setState(() {});
    });
    player.addListener(syncMotion);
    if (widget.autoplay) unawaited(player.start(widget.recordingId));
  }

  @override
  void dispose() {
    player.removeListener(syncMotion);
    motion.dispose();
    positionClock.stop();
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
                  time(scrubPosition ?? visiblePosition),
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
                height: 185,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final visibleDuration = player.duration.clamp(1, 30000);
                    void scrub(double x) => setState(() {
                      scrubPosition =
                          (scrubOriginPosition -
                                  (x - scrubOriginX) /
                                      constraints.maxWidth *
                                      visibleDuration)
                              .round()
                              .clamp(0, player.duration);
                    });
                    void commit() {
                      final target = scrubPosition;
                      setState(() => scrubPosition = null);
                      if (target != null && seekable) {
                        unawaited(player.seek(target));
                      }
                    }

                    return Semantics(
                      label: '재생 위치',
                      value: time(scrubPosition ?? visiblePosition),
                      increasedValue: time(
                        (player.position + 5000).clamp(0, player.duration),
                      ),
                      decreasedValue: time(
                        (player.position - 5000).clamp(0, player.duration),
                      ),
                      onIncrease: seekable
                          ? () => unawaited(
                              player.seek(
                                (player.position + 5000).clamp(
                                  0,
                                  player.duration,
                                ),
                              ),
                            )
                          : null,
                      onDecrease: seekable
                          ? () => unawaited(
                              player.seek(
                                (player.position - 5000).clamp(
                                  0,
                                  player.duration,
                                ),
                              ),
                            )
                          : null,
                      child: GestureDetector(
                        key: const ValueKey('playback-waveform'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: seekable
                            ? (event) {
                                scrubOriginX = event.localPosition.dx;
                                scrubOriginPosition = visiblePosition;
                                setState(() => scrubPosition = visiblePosition);
                              }
                            : null,
                        onHorizontalDragUpdate: seekable
                            ? (event) => scrub(event.localPosition.dx)
                            : null,
                        onHorizontalDragEnd: seekable ? (_) => commit() : null,
                        onHorizontalDragCancel: () =>
                            setState(() => scrubPosition = null),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _Waveform(
                            player.waveform,
                            player.duration == 0
                                ? 0
                                : (scrubPosition ?? visiblePosition) /
                                      player.duration,
                            Theme.of(context).colorScheme.primary,
                            player.duration / visibleDuration,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 112),
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
                            : player.phase == PlaybackPhase.paused ||
                                  (player.phase == PlaybackPhase.completed &&
                                      player.position < player.duration)
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
  _Waveform(this.peaks, this.progress, this.color, this.scale);
  final List<double> peaks;
  final double progress;
  final Color color;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final trackWidth = size.width * scale;
    final step = peaks.isEmpty ? 0.0 : trackWidth / peaks.length;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
    for (var i = 0; i < peaks.length; i++) {
      final height = (peaks[i] * size.height).clamp(1.0, size.height);
      final paint = Paint()
        ..color = color.withValues(
          alpha: i / peaks.length <= progress ? 1 : .25,
        )
        ..strokeWidth = (step * .6).clamp(1.0, 3.0)
        ..strokeCap = StrokeCap.round;
      final x = size.width / 2 + (i + .5) * step - progress * trackWidth;
      if (x < -3 || x > size.width + 3) {
        continue;
      }
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Waveform oldDelegate) =>
      oldDelegate.peaks != peaks ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.scale != scale;
}
