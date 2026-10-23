import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_row_surface.dart';
import 'package:song_record/core/widgets/music_view_data.dart';

import 'app_icon.dart';
import 'song_badges.dart';

class SongRow extends StatelessWidget {
  const SongRow.registered({
    required RegisteredSongViewData this._song,
    this.onTap,
    this.alreadyAdded = false,
    this.trailingAction,
    this.flat = false,
    super.key,
  }) : _candidate = null,
       placement = null,
       rank = null;

  SongRow.candidate({
    required CandidateSongViewData candidate,
    required this.placement,
    this.rank,
    this.onTap,
    this.trailingAction,
    super.key,
  }) : flat = placement != CandidatePlacement.playlist,
       _song = null,
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
  final bool flat;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final song = _song;
    final candidate = _candidate;
    final title = song?.title ?? candidate!.title;
    final artist = song?.artist ?? candidate!.artist;
    final isPlaylist = placement == CandidatePlacement.playlist;
    return MusicRowSurface(
      compact: true,
      flat: flat,
      padding: flat
          ? null
          : const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      minHeight: flat ? 78 : 64,
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
              Text(
                title,
                style: AppTypography.songTitle.copyWith(
                  fontSize: flat ? 16 : 15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                song == null
                    ? (rank == null
                          ? '$artist · ${candidate!.sourceLabel}'
                          : artist)
                    : '$artist · ${formatVersionCode(song.version)}',
                style: AppTypography.supporting.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          );
          final badges = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (song != null) ...[
                TierBadge(formatSongTier(song.tier)),
                if (song.isSuitable)
                  AppIcon(
                    Icons.favorite,
                    size: 19,
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: '나에게 어울리는 곡',
                  ),
                if (!alreadyAdded) MusicalKeyBadge(value: song.musicalKey),
              ],
              if (isPlaylist && trailingAction == null)
                const AppIcon(Icons.chevron_right, size: 16),
              if (alreadyAdded)
                const Text('추가됨', style: AppTypography.supporting),
              ?trailingAction,
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
                  style: AppTypography.detailTitle.copyWith(
                    fontSize: 25,
                    color: rank! <= 3
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (song != null) ...[
                TierBadge(formatSongTier(song.tier)),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(child: copy),
              if (song != null)
                SizedBox(
                  width: 22,
                  child: song.isSuitable
                      ? AppIcon(
                          Icons.favorite,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                          semanticLabel: '나에게 어울리는 곡',
                        )
                      : null,
                ),
              const SizedBox(width: AppSpacing.sm),
              if (alreadyAdded)
                const Text('추가됨', style: AppTypography.supporting)
              else if (song != null)
                MusicalKeyBadge(value: song.musicalKey)
              else if (rank != null)
                Text(
                  candidate!.number,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else if (trailingAction == null)
                const AppIcon(Icons.chevron_right, size: 16),
              ?trailingAction,
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
    final light = Theme.of(context).brightness == Brightness.light;
    final (background, foreground) = switch (keyValue?.mode) {
      KeyMode.male =>
        light
            ? (const Color(0xFFE1EFFF), const Color(0xFF15538A))
            : (const Color(0xFF174A7E), const Color(0xFFD4E9FF)),
      KeyMode.female =>
        light
            ? (const Color(0xFFFCE5F0), const Color(0xFF98345F))
            : (const Color(0xFF6E3051), const Color(0xFFFFE0EF)),
      _ =>
        light
            ? (const Color(0xFFE6E6E6), const Color(0xFF333333))
            : (const Color(0xFF303030), Colors.white),
    };
    return Container(
      width: 44,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          keyValue == null ? '미정' : formatMusicalKey(keyValue),
          style: TextStyle(
            fontSize: AppTypography.keyBadgeSize,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
