import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_view_data.dart';

class SongSummary extends StatelessWidget {
  const SongSummary({required this.song, this.onEdit, super.key});
  final RegisteredSongViewData song;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title, style: AppTypography.detailTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${song.artist} · ${song.tjNumber == null ? "TJ 번호 없음" : "TJ ${song.tjNumber!.value}"}',
                style: const TextStyle(
                  fontSize: AppTypography.songDetailSubtitleSize,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(
              AppDimensions.songSummaryRadius,
            ),
          ),
          child: Padding(
            padding: AppDimensions.songSummaryPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    const Text('곡 정보'),
                    TextButton.icon(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('곡 수정'),
                    ),
                  ],
                ),
                _SummaryValue(
                  label: '버전',
                  value: formatVersionCode(song.version),
                ),
                _SummaryValue(
                  label: '대표 키',
                  value: song.musicalKey == null
                      ? '미정'
                      : formatMusicalKey(song.musicalKey!),
                ),
                _SummaryValue(label: '곡 티어', value: formatSongTier(song.tier)),
                const SizedBox(height: AppSpacing.md),
                const Text('아쉬운 점', style: AppTypography.supporting),
                const SizedBox(height: AppSpacing.xs),
                Text(song.note.trim().isEmpty ? '아직 작성하지 않았어요.' : song.note),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Read-only metadata: the explicit edit button is the only edit entry.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          Text(label, style: AppTypography.supporting),
          Text(value),
        ],
      ),
    );
  }
}
