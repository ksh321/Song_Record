import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_row_surface.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/song_badges.dart';
import 'package:song_record/core/widgets/song_row.dart';

import 'app_icon.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${recording.compactDateLabel}${snapshot.songId == null ? ' · 곡 미연결' : ''}',
                  semanticsLabel:
                      '${recording.dateLabel}${snapshot.songId == null ? ' · 곡 미연결' : ''}',
                  style: AppTypography.supporting.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                    minimumSize: const Size(62, 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                  ),
                  icon: const AppIcon(Icons.play_arrow, size: 16),
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        snapshot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.songTitle.copyWith(height: 1.4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        snapshot.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.supporting.copyWith(
                          fontSize: 11,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MusicalKeyBadge(value: snapshot.key),
              if (selected) const AppIcon(Icons.check, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
