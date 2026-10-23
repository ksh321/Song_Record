import 'package:flutter/material.dart';

/// P05-01: values from docs/reference/ui_reference_palette.json (v1.11).
/// CSS px are logical pixels here; preview device dimensions are not app sizes.
abstract final class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF222222);
  static const raised = Color(0xFF303030);
  static const line = Color(0xFF3B3B3B);
  static const text = Color(0xFFEEEEEE);
  static const muted = Color(0xFFAAAAAA);
  // Shared foreground for every selectable accent and both app themes.
  static const onAccent = Color(0xFFFFFFFF);
  static const danger = Color(0xFFFF9B9F);

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
  static const sheetBackground = Color(0xFF222222);
  static const sheetBorder = Color(0xFF414141);
  static const sheetScrim = Color.fromRGBO(0, 0, 0, 0.48);
  static const focusOutline = Color(0xFFEEEEEE);
}

enum AppAccent {
  blue('blue', '블루', Color(0xFF2C67C5), AppColors.onAccent),
  green('green', '그린', Color(0xFF38813B), AppColors.onAccent),
  yellow('yellow', '옐로', Color(0xFFFFC928), AppColors.onAccent),
  pink('pink', '핑크', Color(0xFFEC4899), AppColors.onAccent),
  orange('orange', '오렌지', Color(0xFFFF851B), AppColors.onAccent),
  purple('purple', '퍼플', Color(0xFF7849D1), AppColors.onAccent),
  white('white', '화이트', Color(0xFFFFFFFF), Color(0xFF000000)),
  neutral('default', '기본값', Color(0xFF737373), AppColors.onAccent);

  const AppAccent(this.id, this.label, this.background, this.foreground);

  // The option labelled "기본값" is grey. The initial selection is blue.
  static const initial = blue;

  final String id;
  final String label;
  final Color background;
  final Color foreground;
}

abstract final class AppTypography {
  // The approved HTML uses Droid Sans Fallback. Bundle the complete AOSP font
  // so labels outside the prototype's small subset also render consistently.
  static const familyStack = <String>[
    'ReferenceKR',
    'Noto Sans KR',
    'Malgun Gothic',
    'sans-serif',
  ];
  static const double baseSize = 14;
  static const double songTitleSize = 16;
  static const double songDetailTitleSize = 26;
  static const double songDetailSubtitleSize = 13;
  static const double supportingTextSize = 12;
  static const double keyBadgeSize = 11;
  static const double tabLabelSize = 9;
  static const double fieldValueSize = 14;
  static const double sheetTitleSize = 19;
  static const double sheetOptionSize = 15;
  static const double roleTitleSize = 13;
  static const double keyWheelSize = 22;
  static const double keyWheelSelectedSize = 28;
  static const buttonWeight = FontWeight.w700;
  // UI_REFERENCE specifies this line height for song list titles.
  static const double songTitleLineHeight = 1.5;

  static const body = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: baseSize,
    color: AppColors.text,
  );
  static const supporting = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: supportingTextSize,
  );
  static const songTitle = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: songTitleSize,
    height: songTitleLineHeight,
    fontWeight: FontWeight.w600,
  );
  static const detailTitle = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: songDetailTitleSize,
    fontWeight: FontWeight.w700,
  );
  static const sheetTitle = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: sheetTitleSize,
    fontWeight: FontWeight.w700,
  );
  static const sheetOption = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: sheetOptionSize,
  );
  // Button colour belongs to its stateful ButtonStyle, not this TextStyle.
  static const button = TextStyle(
    fontFamily: 'ReferenceKR',
    fontSize: baseSize,
    fontWeight: buttonWeight,
  );
}

/// Named component measurements; minimum heights may grow with text scaling.
abstract final class AppDimensions {
  static const double primaryButtonMinHeight = 50;
  static const double primaryButtonRadius = 12;
  static const primaryButtonPadding = EdgeInsets.symmetric(
    vertical: 13,
    horizontal: 18,
  );
  static const double primaryButtonFontSize = 14;
  static const double iconButtonWidth = 44;
  static const double iconButtonHeight = 44;
  static const double fieldMinHeight = 49;
  static const double songEditorFieldMinHeight = 68;
  static const double fieldRadius = 12;
  // Final HTML .field padding; the JSON only specifies height and radius.
  static const fieldPadding = EdgeInsets.symmetric(
    vertical: 12,
    horizontal: 15,
  );
  static const double listCardMinHeight = 90;
  static const double listCardRadius = 14;
  static const double compactSongRowMinHeight = 64;
  static const double compactSongRowPadding = 12;
  static const double recordRowMinHeight = 64;
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
  static const double bottomNavigationHeight = 70;
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
