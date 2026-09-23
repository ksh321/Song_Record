import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';

enum SongDiscoveryDestination { charts, search, mySongs }

/// Retains the originating playlist across catalog navigation. Null is cancel.
class SongDiscoveryResult {
  const SongDiscoveryResult(this.destination, this.playlistId);

  final SongDiscoveryDestination destination;
  final String? playlistId;
}

Future<SongDiscoveryResult?> showSongDiscoverySheet({
  required BuildContext context,
  String? playlistId,
  String? playlistTitle,
}) {
  if (playlistId != null && playlistId.trim().isEmpty) {
    throw ArgumentError.value(playlistId, 'playlistId', '목록 ID가 필요합니다.');
  }
  final media = MediaQuery.of(context);
  return showModalBottomSheet<SongDiscoveryResult>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: AppColors.sheetBackground,
    barrierColor: AppColors.sheetScrim,
    barrierLabel: '새 곡 찾기 취소',
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.sheetTopRadius)),
    ),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(maxHeight: media.size.height * AppDimensions.sheetMaxHeightFactor),
    sheetAnimationStyle: media.disableAnimations || media.accessibleNavigation
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AppDimensions.sheetAnimationDuration,
            reverseDuration: AppDimensions.sheetAnimationDuration,
          ),
    builder: (sheetContext) {
      void choose(SongDiscoveryDestination destination) {
        Navigator.of(sheetContext).pop(SongDiscoveryResult(destination, playlistId));
      }

      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: AppDimensions.sheetPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: const Text('새 곡 찾기', style: AppTypography.sheetTitle)),
              if (playlistTitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(playlistTitle, style: AppTypography.supporting),
              ],
              const SizedBox(height: AppSpacing.lg),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _DiscoveryCard(
                        title: '인기 차트',
                        description: '순위에서 곡 찾아보기',
                        icon: Icons.bar_chart,
                        onTap: () => choose(SongDiscoveryDestination.charts),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.choiceCardGap),
                    Expanded(
                      child: _DiscoveryCard(
                        title: '검색',
                        description: '곡명·가수·번호로 찾기',
                        icon: Icons.search,
                        onTap: () => choose(SongDiscoveryDestination.search),
                      ),
                    ),
                  ],
                ),
              ),
              if (playlistId != null) ...[
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => choose(SongDiscoveryDestination.mySongs),
                  child: const Text('내 곡에서 선택'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('취소')),
            ],
          ),
        ),
      );
    },
  );
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.title, required this.description, required this.icon, required this.onTap});

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.choiceCardRadius),
      side: const BorderSide(color: AppColors.sheetBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimensions.choiceCardMinHeight),
        child: Padding(
          padding: AppDimensions.choiceCardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 23, color: AppColors.muted),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: AppTypography.sheetOption.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              Text(description, style: AppTypography.supporting),
              const SizedBox(height: AppSpacing.sm),
              const Align(alignment: Alignment.centerRight, child: Icon(Icons.chevron_right, size: 14)),
            ],
          ),
        ),
      ),
    ),
  );
}
