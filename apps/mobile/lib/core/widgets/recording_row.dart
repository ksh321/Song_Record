import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_row_surface.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/recording_file_status_card.dart';

class RecordingRow extends StatelessWidget {
  const RecordingRow({
    required this.recording,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final RecordingViewData recording;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Never replace captured title/key/version with a linked song's current data.
    final snapshot = recording.snapshot;
    return MusicRowSurface(
      minHeight: AppDimensions.recordRowMinHeight,
      onTap: onTap,
      selected: selected,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snapshot.title, style: AppTypography.songTitle),
                Text(snapshot.artist, style: AppTypography.supporting),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${recording.dateLabel} · ${recording.durationLabel}',
                  style: AppTypography.supporting,
                ),
                Text(
                  '${formatVersionCode(snapshot.version)} · ${formatMusicalKey(snapshot.key)} · '
                  '티어 ${formatRecordingTier(recording.tier)}',
                  style: AppTypography.supporting,
                ),
                if (recording.fileStatus == null)
                  Text(
                    recording.fileAvailability.label,
                    style: AppTypography.supporting,
                  ),
                if (recording.fileStatus != null)
                  RecordingFileStatusCard(status: recording.fileStatus!),
                if (snapshot.songId == null)
                  const Text('곡 미연결', style: AppTypography.supporting),
                if (selected)
                  const Text('선택됨', style: AppTypography.supporting),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(selected ? Icons.check : Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}
