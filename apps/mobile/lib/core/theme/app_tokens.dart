import 'package:flutter/material.dart';

/// P05-01: values from docs/reference/ui_reference_palette.json (v1.11).
/// CSS px are logical pixels here; preview device dimensions are not app sizes.
abstract final class AppColors {
  static const background = Color(0xFF111111);
  static const surface = Color(0xFF232323);
  static const raised = Color(0xFF303030);
  static const line = Color(0xFF383838);
  static const text = Color(0xFFE7E7E7);
  static const muted = Color(0xFFA8A8A8);
  static const danger = Color(0xFFE7A2A2);

  // Recording has its own meaning and never follows the selected accent.
  static const recording = Color(0xFFE5484D);
  static const onRecording = Color(0xFFFFFFFF);
  static const deleteText = Color(0xFFDD868A);
  static const dangerBorder = Color(0xFF674747);
  static const keyOriginalBackground = Color(0xFF303030);
  static const keyMaleBackground = Color(0xFF213556);
  static const keyFemaleBackground = Color(0xFF46272D);
  static const keyForeground = Color(0xFFFFFFFF);
  static const compactRowBackground = Color(0xFF202020);
  static const compactRowBorder = Color(0xFF353535);
  static const sheetBackground = Color(0xFF232323);
  static const sheetBorder = Color(0xFF414141);
  static const sheetScrim = Color.fromRGBO(0, 0, 0, 0.48);
  static const focusOutline = Color(0xFFE7E7E7);
}

enum AppAccent {
  blue('blue', '블루', Color(0xFF2C67C5), Color(0xFFFFFFFF)),
  green('green', '그린', Color(0xFF38813B), Color(0xFFFFFFFF)),
  yellow('yellow', '옐로', Color(0xFF926C20), Color(0xFFFFFFFF)),
  pink('pink', '핑크', Color(0xFFB44077), Color(0xFFFFFFFF)),
  orange('orange', '오렌지', Color(0xFFB64E1F), Color(0xFFFFFFFF)),
  purple('purple', '퍼플', Color(0xFF7849D1), Color(0xFFFFFFFF)),
  white('white', '화이트', Color(0xFFFFFFFF), Color(0xFF000000)),
  neutral('default', '기본값', Color(0xFF737373), Color(0xFFFFFFFF));

  const AppAccent(this.id, this.label, this.background, this.foreground);

  // The option labelled "기본값" is grey. The initial selection is blue.
  static const initial = blue;

  final String id;
  final String label;
  final Color background;
  final Color foreground;
}

abstract final class AppTypography {
  // No font asset is bundled by this change. Unavailable families fall back
  // to the platform font; final font packaging is a separate decision.
  static const familyStack = <String>[
    'ReferenceKR',
    'Noto Sans KR',
    'Malgun Gothic',
    'sans-serif',
  ];
  static const double baseSize = 14;
  static const double songTitleSize = 15;
  static const double songDetailTitleSize = 20;
  static const double songDetailSubtitleSize = 13;
  static const double supportingTextSize = 12;
  static const double keyBadgeSize = 12;
  static const double tabLabelSize = 12;
  static const double fieldValueSize = 14;
  static const double sheetTitleSize = 19;
  static const double sheetOptionSize = 15;
  static const double roleTitleSize = 13;
  static const double keyWheelSize = 22;
  static const double keyWheelSelectedSize = 28;
  static const buttonWeight = FontWeight.w700;
  // UI_REFERENCE specifies this line height for song list titles.
  static const double songTitleLineHeight = 1.5;

  static const body = TextStyle(fontSize: baseSize, color: AppColors.text);
  static const supporting = TextStyle(
    fontSize: supportingTextSize,
    color: AppColors.muted,
  );
  static const songTitle = TextStyle(
    fontSize: songTitleSize,
    height: songTitleLineHeight,
    color: AppColors.text,
  );
  static const detailTitle = TextStyle(
    fontSize: songDetailTitleSize,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const sheetTitle = TextStyle(
    fontSize: sheetTitleSize,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const sheetOption = TextStyle(
    fontSize: sheetOptionSize,
    color: AppColors.text,
  );
  // Button colour belongs to its stateful ButtonStyle, not this TextStyle.
  static const button = TextStyle(fontSize: baseSize, fontWeight: buttonWeight);
}

/// Named component measurements; minimum heights may grow with text scaling.
abstract final class AppDimensions {
  static const double primaryButtonMinHeight = 52;
  static const double primaryButtonRadius = 28;
  static const primaryButtonPadding = EdgeInsets.symmetric(
    vertical: 13,
    horizontal: 18,
  );
  static const double primaryButtonFontSize = 14;
  static const double iconButtonWidth = 44;
  static const double iconButtonHeight = 44;
  static const double fieldMinHeight = 71;
  static const double songEditorFieldMinHeight = 68;
  static const double fieldRadius = 9;
  // Final HTML .field padding; the JSON only specifies height and radius.
  static const fieldPadding = EdgeInsets.symmetric(
    vertical: 12,
    horizontal: 15,
  );
  static const double listCardMinHeight = 90;
  static const double listCardRadius = 22;
  static const double compactSongRowMinHeight = 66;
  static const double compactSongRowPadding = 12;
  static const double recordRowMinHeight = 86;
  static const int choiceCardColumns = 2;
  static const double choiceCardGap = 12;
  static const double choiceCardRadius = 18;
  static const double choiceCardMinHeight = 156;
  static const choiceCardPadding = EdgeInsets.symmetric(
    vertical: 18,
    horizontal: 16,
  );
  static const int viewToggleColumns = 2;
  static const double viewToggleGap = 7;
  static const double viewToggleMinHeight = 44;
  static const double viewToggleRadius = 8;
  static const double songSummaryRadius = 18;
  static const songSummaryPadding = EdgeInsets.fromLTRB(16, 4, 16, 16);
  static const double recordRoleRowMinHeight = 62;
  static const recordRoleRowPadding = EdgeInsets.symmetric(vertical: 9);
  static const double sheetTopRadius = 25;
  static const double sheetMaxHeightFactor = 0.9;
  static const sheetPadding = EdgeInsets.fromLTRB(24, 12, 24, 28);
  static const sheetAnimationDuration = Duration(milliseconds: 180);
  static const double keyWheelHeight = 220;
  static const double keyWheelItemHeight = 44;
  static const double keyWheelVerticalPadding = 88;
  static const int keyWheelMin = -12;
  static const int keyWheelMax = 12;
  static const bool keyWheelWrap = false;
  static const double recordRingSize = 82;
  static const double recordRingBorderWidth = 3;
  static const double recordStartCircleSize = 64;
  static const double recordStopSquareSize = 32;
  static const double recordStopSquareRadius = 6;
  static const double bottomNavigationHeight = 76;
  static const double metadataFieldMinHeight = 44;
  static const double metadataTextareaMinHeight = 120;
  static const double metadataGap = 14;
  static const double metadataRadius = 9;
}

/// Common spacing present in the final HTML / UI_REFERENCE.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 28;
}
