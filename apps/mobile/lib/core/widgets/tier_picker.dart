import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';

const _guidance = [
  '음정·박자·호흡이 안정적이고 끝까지 여유 있게 소화해요.',
  '대체로 안정적이고 일부 구간만 보완하면 돼요.',
  '완곡은 가능하지만 흔들리는 구간이 반복돼요.',
  '자주 막히는 구간이 있어 부분 연습이 필요해요.',
  '아직 완곡이 어려워 구간별로 익히는 단계예요.',
];

abstract final class TierPicker {
  static Future<SelectionResult<SongTier?>?> song({
    required BuildContext context,
    required SongTier? selected,
  }) => showSelectionSheet<SongTier?>(
    context: context,
    title: '곡 티어',
    description: '평소 이 곡을 부르는 상태를 기준으로 선택해 주세요.',
    selected: selected,
    options: [
      for (final tier in SongTier.values)
        SelectionOption(
          tier,
          formatSongTier(tier),
          description: _guidance[tier.index],
        ),
      const SelectionOption(null, '미정', description: '아직 평가하지 않았어요.'),
    ],
  );

  static Future<SelectionResult<RecordingTier?>?> recording({
    required BuildContext context,
    required RecordingTier? selected,
  }) => showSelectionSheet<RecordingTier?>(
    context: context,
    title: '녹음 티어',
    description: '이 녹음을 기준으로 선택해 주세요.',
    selected: selected,
    options: [
      for (final tier in RecordingTier.values)
        SelectionOption(
          tier,
          formatRecordingTier(tier),
          description: _guidance[tier.index],
        ),
      const SelectionOption(null, '미정', description: '아직 평가하지 않았어요.'),
    ],
  );
}
