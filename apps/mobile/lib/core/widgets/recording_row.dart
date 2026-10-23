import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_row_surface.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/song_badges.dart';
import 'package:song_record/core/widgets/song_row.dart';

class RecordingRow extends StatelessWidget {
  const RecordingRow({
    required this.recording,
    this.onTap,
    this.onPlay,
    this.selected = false,
    super.key,
  });

  final RecordingViewData recording;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Never replace captured title/key/version with a linked song's current data.
    final snapshot = recording.snapshot;
    return MusicRowSurface(
      minHeight: 64,
      onTap: onTap,
      selected: selected,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${recording.dateLabel}${snapshot.songId == null ? ' · 곡 미연결' : ''}',
                  style: AppTypography.supporting,
                ),
              ),
              Tooltip(
                message: recording.fileStatus?.canPlay == false
                    ? recording.fileStatus!.playbackUnavailableLabel
                    : '재생',
                child: FilledButton.icon(
                  onPressed: recording.fileStatus?.canPlay == false
                      ? null
                      : onPlay,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(
                    recording.durationLabel,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              TierBadge(formatRecordingTier(recording.tier), size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snapshot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.songTitle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  snapshot.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.supporting,
                ),
              ),
              const SizedBox(width: 8),
              MusicalKeyBadge(value: snapshot.key),
              if (selected) const Icon(Icons.check, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
