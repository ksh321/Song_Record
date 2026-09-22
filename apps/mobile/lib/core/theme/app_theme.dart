import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/core/theme/app_tokens.dart';

abstract final class AppTheme {
  static ThemeData dark({AppAccent accent = AppAccent.initial}) {
    // Explicit colours preserve the reference palette; no generated seed hues.
    final scheme = ColorScheme.dark(
      primary: accent.background,
      onPrimary: accent.foreground,
      primaryContainer: accent.background,
      onPrimaryContainer: accent.foreground,
      primaryFixed: accent.background,
      primaryFixedDim: accent.background,
      onPrimaryFixed: accent.foreground,
      onPrimaryFixedVariant: accent.foreground,
      secondary: AppColors.raised,
      onSecondary: AppColors.text,
      secondaryContainer: AppColors.raised,
      onSecondaryContainer: AppColors.text,
      secondaryFixed: AppColors.raised,
      secondaryFixedDim: AppColors.raised,
      onSecondaryFixed: AppColors.text,
      onSecondaryFixedVariant: AppColors.muted,
      tertiary: accent.background,
      onTertiary: accent.foreground,
      tertiaryContainer: AppColors.raised,
      onTertiaryContainer: AppColors.text,
      tertiaryFixed: AppColors.raised,
      tertiaryFixedDim: AppColors.raised,
      onTertiaryFixed: AppColors.text,
      onTertiaryFixedVariant: AppColors.muted,
      error: AppColors.danger,
      onError: AppColors.background,
      errorContainer: AppColors.surface,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.raised,
      surfaceContainerHighest: AppColors.raised,
      surfaceDim: AppColors.background,
      surfaceBright: AppColors.raised,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
      surfaceTint: Colors.transparent,
      scrim: AppColors.sheetScrim,
      shadow: Colors.black,
      inverseSurface: AppColors.text,
      onInverseSurface: AppColors.background,
      inversePrimary: accent.background,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      applyElevationOverlayColor: false,
      fontFamilyFallback: AppTypography.familyStack,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      disabledColor: AppColors.muted,
      dividerColor: AppColors.line,
      focusColor: AppColors.focusOutline.withValues(alpha: 0.16),
      textTheme: const TextTheme(
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.supporting,
        titleLarge: AppTypography.detailTitle,
        titleMedium: AppTypography.songTitle,
        titleSmall: TextStyle(
          fontSize: AppTypography.roleTitleSize,
          color: AppColors.text,
        ),
        headlineSmall: AppTypography.detailTitle,
        labelLarge: AppTypography.button,
        labelMedium: AppTypography.supporting,
        labelSmall: AppTypography.supporting,
      ),
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTypography.detailTitle,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.listCardRadius),
          ),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _filledStyle(accent.background, accent.foreground),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedStyle(AppColors.text, AppColors.line),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size(0, AppDimensions.iconButtonHeight),
          textStyle: AppTypography.button,
        ).copyWith(side: _focusSide),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.text,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size(
            AppDimensions.iconButtonWidth,
            AppDimensions.iconButtonHeight,
          ),
          focusColor: AppColors.focusOutline.withValues(alpha: 0.16),
        ).copyWith(side: _focusSide),
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        constraints: BoxConstraints(minHeight: AppDimensions.fieldMinHeight),
        contentPadding: AppDimensions.fieldPadding,
        labelStyle: AppTypography.supporting,
        hintStyle: AppTypography.supporting,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.fieldRadius),
          ),
          borderSide: BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.fieldRadius),
          ),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.fieldRadius),
          ),
          borderSide: BorderSide(color: AppColors.focusOutline, width: 2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.sheetBackground,
        modalBackgroundColor: AppColors.sheetBackground,
        modalBarrierColor: AppColors.sheetScrim,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimensions.sheetTopRadius),
          ),
          side: BorderSide(color: AppColors.sheetBorder),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppDimensions.bottomNavigationHeight,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.background,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: AppTypography.tabLabelSize,
            color: AppColors.text,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent.foreground
                : AppColors.muted,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent.background,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.text,
        selectionColor: accent.background.withValues(alpha: 0.3),
        selectionHandleColor: accent.background,
      ),
    );
  }

  static ButtonStyle get recordingFilledButtonStyle =>
      _filledStyle(AppColors.recording, AppColors.onRecording);

  static ButtonStyle get recordingOutlinedButtonStyle =>
      _outlinedStyle(AppColors.recording, AppColors.recording);

  static final _focusSide = WidgetStateProperty.resolveWith<BorderSide>(
    (states) => BorderSide(
      color:
          !states.contains(WidgetState.disabled) &&
              states.contains(WidgetState.focused)
          ? AppColors.focusOutline
          : Colors.transparent,
      width: 2,
    ),
  );

  static ButtonStyle _filledStyle(Color background, Color foreground) =>
      FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: AppColors.raised,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(0, AppDimensions.primaryButtonMinHeight),
        padding: AppDimensions.primaryButtonPadding,
        textStyle: AppTypography.button,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.primaryButtonRadius),
          ),
        ),
      ).copyWith(side: _focusSide);

  static ButtonStyle _outlinedStyle(Color foreground, Color border) =>
      OutlinedButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(0, AppDimensions.primaryButtonMinHeight),
        padding: AppDimensions.primaryButtonPadding,
        textStyle: AppTypography.button,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppDimensions.primaryButtonRadius),
          ),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? AppColors.line
                : states.contains(WidgetState.focused)
                ? AppColors.focusOutline
                : border,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
      );
}
