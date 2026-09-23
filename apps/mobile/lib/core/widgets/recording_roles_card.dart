import 'package:flutter/material.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_view_data.dart';

class RecordingRolesCard extends StatelessWidget {
  RecordingRolesCard({
    required this.songId,
    required this.selection,
    required Map<RecordingId, RecordingViewData> recordings,
    this.onChooseRepresentative,
    this.onOpenRecording,
    super.key,
  }) : recordings = Map.unmodifiable(recordings) {
    for (final id in selection.uniqueIds) {
      final recording = this.recordings[id];
      if (recording == null ||
          recording.id != id ||
          recording.snapshot.songId != songId) {
        throw ArgumentError('역할에 지정된 녹음은 같은 곡의 표시 데이터가 필요합니다.');
      }
    }
  }

  final SongId songId;
  final RecordingSelection selection;
  final Map<RecordingId, RecordingViewData> recordings;
  final VoidCallback? onChooseRepresentative;
  final ValueChanged<RecordingId>? onOpenRecording;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppDimensions.songSummaryRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                const Text('녹음 보관'),
                Text(
                  '자동 보관 대상 ${selection.uniqueIds.length}개',
                  style: AppTypography.supporting,
                ),
              ],
            ),
            _role(
              label: '대표 녹음',
              id: selection.representative,
              empty: '미지정 · 직접 골라 주세요',
              action: selection.representative == null ? '지정' : '변경',
              onTap: onChooseRepresentative,
            ),
            _role(label: '최신 녹음', id: selection.latest, empty: '녹음 없음'),
            _role(
              label: '최저 티어 녹음',
              id: selection.lowestTier,
              empty: '평가된 녹음 없음',
            ),
            const Divider(),
            // Only this explanation collapses; all three role rows stay visible.
            ExpansionTile(
              key: PageStorageKey('recording-retention-${songId.value}'),
              expansionAnimationStyle:
                  MediaQuery.of(context).disableAnimations ||
                      MediaQuery.of(context).accessibleNavigation
                  ? AnimationStyle.noAnimation
                  : null,
              title: const Text('자동 보관 기준', style: AppTypography.supporting),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: const [
                Text(
                  '대표·최신·최저 티어 녹음을 자동 보관해요. 같은 녹음이 여러 역할을 맡으면 한 번만 세어요. '
                  '보관 대상으로 선정되어도 파일이 서버에 있다는 뜻은 아니에요. '
                  '키·버전·실제 파일 상태는 녹음 상세에서 확인하세요.',
                  style: AppTypography.supporting,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _role({
    required String label,
    required RecordingId? id,
    required String empty,
    String? action,
    VoidCallback? onTap,
  }) {
    final recording = id == null ? null : recordings[id];
    final tap = action != null
        ? onTap
        : id == null || onOpenRecording == null
        ? null
        : () => onOpenRecording!(id);
    return Semantics(
      button: true,
      enabled: tap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimensions.recordRoleRowMinHeight,
            ),
            child: Padding(
              padding: AppDimensions.recordRoleRowPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: AppTypography.roleTitleSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          recording == null
                              ? empty
                              : '${recording.dateLabel} · ${recording.durationLabel} · ${formatRecordingTier(recording.tier)}',
                          style: AppTypography.supporting,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (action != null)
                    Text(action, style: AppTypography.supporting)
                  else if (recording != null)
                    const Icon(Icons.chevron_right, size: 16)
                  else
                    const Text('—', style: AppTypography.supporting),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
