import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_appearance.dart';
import 'package:song_record/core/theme/app_theme.dart';

void main() {
  testWidgets('appearance changes preserve the mounted input draft', (t) async {
    final light = ValueNotifier(false);
    final draft = TextEditingController(text: '저장 전 메모');
    addTearDown(light.dispose);
    addTearDown(draft.dispose);
    await t.pumpWidget(
      AppAppearance(
        light: light,
        child: ValueListenableBuilder(
          valueListenable: light,
          builder: (_, value, _) => MaterialApp(
            theme: AppTheme.preview(light: value),
            home: Scaffold(
              appBar: AppBar(actions: const [ThemeToggle()]),
              body: TextField(key: const ValueKey('draft'), controller: draft),
            ),
          ),
        ),
      ),
    );
    final original = t.element(find.byKey(const ValueKey('draft')));
    for (final label in ['다크 모드 끄기', '다크 모드 켜기']) {
      await t.tap(find.byTooltip(label));
      await t.pumpAndSettle();
      expect(t.element(find.byKey(const ValueKey('draft'))), same(original));
      expect(draft.text, '저장 전 메모');
    }
  });
}
