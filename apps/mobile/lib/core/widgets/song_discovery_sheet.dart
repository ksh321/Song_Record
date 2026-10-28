import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/sheet_safe_area.dart';

import 'app_icon.dart';
import 'feature_icon.dart';

enum SongDiscoveryDestination { charts, search, mySongs, manual }

/// Retains the originating playlist across catalog navigation. Null is cancel.
class SongDiscoveryResult {
  const SongDiscoveryResult(this.destination, this.playlistId);

  final SongDiscoveryDestination destination;
  final String? playlistId;
}

class SongSourceOption {
  const SongSourceOption(this.value, this.title, this.description, this.icon);
  final String value, title, description;
  final IconData icon;
}

Future<String?> showSongSourceSheet({
  required BuildContext context,
  required List<SongSourceOption> options,
  String title = '새 곡 찾기',
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SheetSafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: AppDimensions.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: AppTypography.sheetTitle)),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('닫기'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < options.length; index += 2) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var column = index;
                      column < index + 2 && column < options.length;
                      column++
                    ) ...[
                      if (column > index) const SizedBox(width: 12),
                      Expanded(
                        child: _DiscoveryCard(
                          title: options[column].title,
                          description: options[column].description,
                          icon: options[column].icon,
                          onTap: () => Navigator.pop(
                            sheetContext,
                            options[column].value,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<SongDiscoveryResult?> showSongDiscoverySheet({
  required BuildContext context,
  String? playlistId,
  String? playlistTitle,
}) async {
  if (playlistId != null && playlistId.trim().isEmpty) {
    throw ArgumentError('목록 ID가 필요합니다.');
  }
  final result = await showSongSourceSheet(
    context: context,
    options: [
      if (playlistId != null)
        const SongSourceOption(
          'mySongs',
          '내 곡에서 추가',
          '등록해 둔 곡에서 선택',
          Icons.music_note_outlined,
        ),
      const SongSourceOption('charts', '인기 차트', '순위에서 곡 찾아보기', Icons.bar_chart),
      const SongSourceOption('search', '검색', '곡명·가수·번호로 찾기', Icons.search),
      const SongSourceOption(
        'manual',
        '직접 등록',
        '곡명과 가수를 직접 입력',
        Icons.edit_outlined,
      ),
    ],
  );
  return result == null
      ? null
      : SongDiscoveryResult(
          SongDiscoveryDestination.values.byName(result),
          playlistId,
        );
}

Future<String?> showRecordingSourceSheet(
  BuildContext context,
) => showSongSourceSheet(
  context: context,
  title: '곡 선택',
  options: const [
    SongSourceOption('songs', '내 곡', '등록해 둔 곡에서 선택', Icons.music_note_outlined),
    SongSourceOption(
      'playlist',
      '플레이리스트',
      '목록에 담아 둔 곡에서 선택',
      Icons.queue_music,
    ),
    SongSourceOption('search', '검색', '곡명·가수·번호로 찾기', Icons.search),
    SongSourceOption('manual', '직접 등록', '곡명과 가수를 직접 입력', Icons.edit_outlined),
  ],
);

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.choiceCardRadius),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppDimensions.choiceCardMinHeight,
        ),
        child: Padding(
          padding: AppDimensions.choiceCardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FeatureIcon(icon),
                  const Spacer(),
                  const AppIcon(Icons.chevron_right, size: 14),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: AppTypography.sheetOption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(description, style: AppTypography.supporting),
            ],
          ),
        ),
      ),
    ),
  );
}
