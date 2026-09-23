import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';

abstract final class VersionPicker {
  static Future<SelectionResult<VersionCode>?> show({
    required BuildContext context,
    required VersionCode selected,
  }) => showSelectionSheet<VersionCode>(
    context: context,
    title: '버전 선택',
    description: '일반 반주가 기본값이에요. 편집 중인 곡 또는 녹음에 적용할 버전을 선택해 주세요.',
    selected: selected,
    options: [
      for (final version in VersionCode.values)
        SelectionOption(version, formatVersionCode(version)),
    ],
  );
}
