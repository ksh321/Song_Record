import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Search and charts use the same centered confirmation and result values.
Future<String?> showKaraokeCandidateDialog({
  required BuildContext context,
  required String title,
  required String artist,
  required String number,
  required bool isTj,
  bool allowSelect = true,
  bool allowFindTj = true,
}) => showDialog<String>(
  context: context,
  builder: (dialogContext) => Dialog(
    child: SingleChildScrollView(
      padding: AppDimensions.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('곡 선택', style: AppTypography.detailTitle),
          const SizedBox(height: 16),
          Text(title, style: AppTypography.songTitle),
          Text(artist),
          Text('${isTj ? 'TJ' : '금영'} $number'),
          const SizedBox(height: 16),
          if (!isTj) ...[
            const Text('금영 결과는 직접 등록할 수 없어요. TJ에서 찾아 선택해 주세요.'),
            if (allowFindTj)
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'find-tj'),
                child: const Text('TJ에서 이 곡 찾기'),
              ),
          ] else if (allowSelect)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'use-tj'),
              child: const Text('곡 선택'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
        ],
      ),
    ),
  ),
);
