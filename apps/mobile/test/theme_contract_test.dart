import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';

void main() {
  // Independent source of truth: the original checked-in reference JSON.
  final reference = jsonDecode(
    File('../../docs/reference/ui_reference_palette.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final colors = reference['colors'] as Map<String, dynamic>;
  final semantic = reference['semanticColors'] as Map<String, dynamic>;
  final accents = (reference['accents'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final components = reference['components'] as Map<String, dynamic>;
  final primaryButton = components['primaryButton'] as Map<String, dynamic>;

  Color hex(Object? value) =>
      Color(0xFF000000 | int.parse((value as String).substring(1), radix: 16));

  test('8가지 강조색의 순서·이름·배경·글자는 원본 JSON과 일치한다', () {
    expect(AppAccent.initial.id, reference['defaultAccentId']);
    expect(
      AppAccent.values.map((accent) => accent.id),
      accents.map((accent) => accent['id']),
    );
    for (var i = 0; i < accents.length; i++) {
      final accent = AppAccent.values[i];
      expect(accent.label, accents[i]['label']);
      expect(accent.background, hex(accents[i]['background']));
      expect(accent.foreground, hex(accents[i]['foreground']));
      final theme = AppTheme.dark(accent: accent);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, hex(colors['bg']));
      expect(theme.colorScheme.surface, hex(colors['surface']));
      expect(theme.colorScheme.onSurface, hex(colors['text']));
      expect(theme.colorScheme.onSurfaceVariant, hex(colors['muted']));
      expect(theme.colorScheme.outline, hex(colors['line']));
      expect(theme.colorScheme.error, hex(colors['danger']));
      expect(theme.colorScheme.primary, hex(accents[i]['background']));
      expect(theme.colorScheme.onPrimary, hex(accents[i]['foreground']));

      final style = theme.filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), hex(accents[i]['background']));
      expect(style.foregroundColor!.resolve({}), hex(accents[i]['foreground']));
      expect(
        style.minimumSize!.resolve({})!.height,
        primaryButton['minHeight'],
      );
      expect(style.fixedSize, isNull, reason: '큰 글꼴에서 높이가 늘어날 수 있어야 한다');
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled}),
        hex(colors['raised']),
      );
      expect(
        style.foregroundColor!.resolve({WidgetState.disabled}),
        hex(colors['muted']),
      );
      expect(
        style.side!.resolve({WidgetState.focused})!.color,
        hex(semantic['focusOutline']),
      );

      final selectedIcon = theme.navigationBarTheme.iconTheme!.resolve({
        WidgetState.selected,
      })!;
      expect(selectedIcon.color, hex(accents[i]['foreground']));
    }
  });

  test('녹음 전용 색과 키 배지는 강조색 선택과 독립적이다', () {
    expect(AppColors.recording, hex(semantic['recording']));
    expect(
      AppColors.keyOriginalBackground,
      hex(semantic['keyOriginalBackground']),
    );
    expect(AppColors.keyMaleBackground, hex(semantic['keyMaleBackground']));
    expect(AppColors.keyFemaleBackground, hex(semantic['keyFemaleBackground']));
    expect(AppColors.keyForeground, hex(semantic['keyForeground']));
    expect(AppColors.sheetBackground, hex(semantic['sheetBackground']));
    expect(AppColors.deleteText, hex(semantic['deleteText']));
    expect(
      AppTheme.recordingFilledButtonStyle.backgroundColor!.resolve({}),
      hex(semantic['recording']),
    );
    expect(
      AppTheme.recordingOutlinedButtonStyle.foregroundColor!.resolve({}),
      hex(semantic['recording']),
    );
  });

  testWidgets('큰 글꼴의 긴 버튼은 최소 높이보다 커질 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: FilledButton(
                  onPressed: () {},
                  child: const Text('길이가 긴 곡 이름을 확인하고 저장하기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThan(AppDimensions.primaryButtonMinHeight),
    );
    expect(tester.takeException(), isNull);
  });
}
