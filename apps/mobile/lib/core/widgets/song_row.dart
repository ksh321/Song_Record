import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_row_surface.dart';
import 'package:song_record/core/widgets/music_view_data.dart';

class SongRow extends StatelessWidget {
  const SongRow.registered({
    required RegisteredSongViewData this._song,
    this.onTap,
    this.alreadyAdded = false,
    super.key,
  }) : _candidate = null,
       placement = null,
       rank = null;

  SongRow.candidate({
    required CandidateSongViewData candidate,
    required this.placement,
    this.rank,
    this.onTap,
    super.key,
  }) : _song = null,
       _candidate = candidate,
       alreadyAdded = false {
    if (placement == null ||
        (placement == CandidatePlacement.chart &&
            (rank == null || rank! < 1)) ||
        (placement != CandidatePlacement.chart && rank != null)) {
      throw ArgumentError('차트 후보에만 양수 순위를 지정하세요.');
    }
    if (placement == CandidatePlacement.playlist &&
        candidate.brand != CatalogBrand.tj) {
      throw ArgumentError('플레이리스트 미등록 후보는 TJ만 허용합니다.');
    }
  }

  final RegisteredSongViewData? _song;
  final CandidateSongViewData? _candidate;
  final CandidatePlacement? placement;
  final int? rank;
  final VoidCallback? onTap;
  final bool alreadyAdded;

  @override
  Widget build(BuildContext context) {
    final song = _song;
    final candidate = _candidate;
    final title = song?.title ?? candidate!.title;
    final artist = song?.artist ?? candidate!.artist;
    final isPlaylist = placement == CandidatePlacement.playlist;
    return MusicRowSurface(
      compact: true,
      minHeight: AppDimensions.compactSongRowMinHeight,
      enabled: !alreadyAdded,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTypography.songTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                song == null
                    ? artist
                    : '$artist · ${formatVersionCode(song.version)}',
                style: AppTypography.supporting,
              ),
              if (candidate != null && !isPlaylist) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(candidate.sourceLabel, style: AppTypography.supporting),
              ],
            ],
          );
          final badges = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (song != null) ...[
                Text(
                  '티어 ${formatSongTier(song.tier)}',
                  style: AppTypography.supporting,
                ),
                if (!alreadyAdded) MusicalKeyBadge(value: song.musicalKey),
              ],
              if (isPlaylist)
                const Text('내 곡 미등록', style: AppTypography.supporting),
              if (alreadyAdded)
                const Text('추가됨', style: AppTypography.supporting),
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rank != null)
                  Text('$rank위', style: AppTypography.songTitle),
                copy,
                if (song != null || isPlaylist) ...[
                  const SizedBox(height: AppSpacing.sm),
                  badges,
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (rank != null) ...[
                Text(
                  '$rank',
                  semanticsLabel: '$rank위',
                  style: AppTypography.detailTitle,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (song != null) ...[
                Text(
                  formatSongTier(song.tier),
                  semanticsLabel: '곡 티어 ${formatSongTier(song.tier)}',
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(child: copy),
              const SizedBox(width: AppSpacing.sm),
              if (alreadyAdded)
                const Text('추가됨', style: AppTypography.supporting)
              else if (song != null)
                MusicalKeyBadge(value: song.musicalKey)
              else if (isPlaylist)
                const Text('내 곡 미등록', style: AppTypography.supporting)
              else
                const Icon(Icons.chevron_right, size: 16),
            ],
          );
        },
      ),
    );
  }
}

class MusicalKeyBadge extends StatelessWidget {
  const MusicalKeyBadge({required this.value, super.key});
  final MusicalKey? value;

  @override
  Widget build(BuildContext context) {
    final keyValue = value;
    final color = switch (keyValue?.mode) {
      KeyMode.male => AppColors.keyMaleBackground,
      KeyMode.female => AppColors.keyFemaleBackground,
      _ => AppColors.keyOriginalBackground,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDimensions.fieldRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          keyValue == null ? '미정' : formatMusicalKey(keyValue),
          style: const TextStyle(
            fontSize: AppTypography.keyBadgeSize,
            color: AppColors.keyForeground,
          ),
        ),
      ),
    );
  }
}
