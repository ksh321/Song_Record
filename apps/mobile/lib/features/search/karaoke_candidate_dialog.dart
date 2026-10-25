import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/feature_icon.dart';
import 'karaoke_search.dart';

class CandidateMembership {
  const CandidateMembership({this.songId, this.playlistCount = 0});
  final String? songId;
  final int playlistCount;
}

class KaraokeCandidateActions {
  const KaraokeCandidateActions({
    required this.membership,
    required this.openSong,
    required this.addToPlaylist,
  });
  final Future<CandidateMembership> Function(String number) membership;
  final Future<void> Function(BuildContext context, String songId) openSong;
  final Future<void> Function(BuildContext context, KaraokeCandidate candidate)
  addToPlaylist;
}

/// Search and charts share the entire candidate window and its theme surface.
Future<String?> showKaraokeCandidateDialog({
  required BuildContext context,
  required String title,
  required String artist,
  required String number,
  required bool isTj,
  bool allowSelect = true,
  bool allowFindTj = true,
  KaraokeCandidateActions? actions,
}) {
  final membership = actions == null || !isTj
      ? null
      : actions.membership(number);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        padding: AppDimensions.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('곡 선택', style: AppTypography.sheetTitle),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('닫기'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${isTj ? 'TJ' : '금영'} $number',
              style: AppTypography.supporting,
            ),
            const SizedBox(height: 8),
            Text(title, style: AppTypography.detailTitle),
            Text(artist),
            const SizedBox(height: 12),
            if (!isTj) ...[
              const Text('금영 곡은 TJ에서 같은 곡을 찾아 선택해 주세요.'),
              if (allowFindTj)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, 'find-tj'),
                  child: const Text('TJ에서 이 곡 찾기'),
                ),
            ] else if (membership != null)
              FutureBuilder<CandidateMembership>(
                future: membership,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('곡 정보를 확인하지 못했어요. 닫고 다시 선택해 주세요.');
                  }
                  final value = snapshot.data;
                  if (value == null) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${value.songId == null ? '내 곡 미등록' : '내 곡에 있음'}${value.playlistCount == 0 ? '' : ' · 플리 ${value.playlistCount}개에 담김'}',
                        style: AppTypography.supporting,
                      ),
                      const SizedBox(height: 20),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _CandidateCard(
                                title: value.songId == null
                                    ? '내 곡 등록'
                                    : '내 곡 보기',
                                description: value.songId == null
                                    ? '이 TJ 번호의 곡을 내 곡에 저장'
                                    : '내 곡에서 관리하기',
                                icon: Icons.music_note_outlined,
                                onTap: () => Navigator.pop(
                                  dialogContext,
                                  value.songId == null
                                      ? 'use-tj'
                                      : 'view-song:${value.songId}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CandidateCard(
                                title: '플레이리스트에 추가',
                                description: '목록을 선택해 담기',
                                icon: Icons.playlist_add,
                                onTap: () => Navigator.pop(
                                  dialogContext,
                                  'add-playlist',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              )
            else if (allowSelect)
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'use-tj'),
                child: const Text('곡 선택'),
              ),
            if (actions == null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });
  final String title, description;
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FeatureIcon(icon, size: 36),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(description, style: AppTypography.supporting),
          ],
        ),
      ),
    ),
  );
}
