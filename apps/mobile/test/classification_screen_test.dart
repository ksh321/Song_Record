import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/settings/accent_preferences.dart';
import 'package:song_record/features/settings/classification_screen.dart';
import 'package:song_record/features/settings/settings_api.dart';

const id = '11111111-1111-4111-8111-111111111111';
ClassificationData data({bool archived = false}) => (
  tags: [
    {
      'id': id,
      'name': '연습',
      'revision': 7,
      'archived_at': archived ? '2026-10-12T00:00:00Z' : null,
    },
  ],
  conditions: [
    for (final c in ['VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'])
      {'code': c, 'name': c},
  ],
);
void main() {
  testWidgets(
    'eight device accents persist through the dedicated channel only',
    (t) async {
      String? saved;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceAccentPreferences.channel, (
            call,
          ) async {
            methods.add(call.method);
            if (call.method == 'writeAccent') {
              saved = (call.arguments as Map)['accent'] as String;
            }
            return call.method == 'readAccent' ? saved : null;
          });
      const preferences = DeviceAccentPreferences();
      expect(await preferences.read(), isNull);
      for (final accent in AppAccent.values) {
        await preferences.write(accent);
        expect(await preferences.read(), accent);
      }
      expect(AppAccent.values, hasLength(8));
      expect(methods.toSet(), {'readAccent', 'writeAccent'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceAccentPreferences.channel, null);
    },
  );
  testWidgets(
    'archive cancellation sends nothing; archive preserves definition display',
    (t) async {
      final accent = ValueNotifier(AppAccent.blue);
      var archived = false;
      final commands = <Map<String, Object?>>[];
      await t.pumpWidget(
        MaterialApp(
          home: ClassificationScreen(
            load: () async => data(archived: archived),
            requireCurrent: () {},
            accent: accent,
            saveAccent: (a) async => accent.value = a,
            command: (method, path, body, op) async {
              commands.add({'method': method, 'path': path, 'body': body});
              archived = true;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('보관'), 300);
      await t.tap(find.text('보관'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(commands, isEmpty);
      await t.tap(find.text('보관'));
      await t.pumpAndSettle();
      await t.tap(find.text('보관').last);
      await t.pumpAndSettle();
      expect(commands.single, {
        'method': 'POST',
        'path': '/v1/tags/$id/archive',
        'body': {'base_revision': 7},
      });
      await t.scrollUntilVisible(find.text('보관됨 · 신규 선택에서 숨김'), 300);
      expect(find.text('연습'), findsOneWidget);
      expect(find.text('보관됨 · 신규 선택에서 숨김'), findsOneWidget);
      expect(find.text('이름 변경'), findsNothing);
      await t.pumpWidget(const SizedBox());
      accent.dispose();
    },
  );
  testWidgets('tag input validates code points without truncating the draft', (
    t,
  ) async {
    final accent = ValueNotifier(AppAccent.blue);
    var sent = 0;
    await t.pumpWidget(
      MaterialApp(
        home: ClassificationScreen(
          load: () async => data(),
          requireCurrent: () {},
          accent: accent,
          saveAccent: (_) async {},
          command: (_, _, _, _) async {
            sent++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('태그 만들기'), 300);
    await t.tap(find.text('태그 만들기'));
    await t.pumpAndSettle();
    final raw = List.filled(51, '😀').join();
    await t.enterText(find.byType(TextField), raw);
    await t.tap(find.text('저장'));
    await t.pumpAndSettle();
    expect(sent, 0);
    expect(find.textContaining('1~50자로'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, raw);
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    accent.dispose();
  });
  testWidgets('account switch hides late tag data', (t) async {
    final result = Completer<ClassificationData>(),
        n = ChangeNotifier(),
        accent = ValueNotifier(AppAccent.blue);
    var active = true;
    await t.pumpWidget(
      MaterialApp(
        home: ClassificationScreen(
          load: () => result.future,
          requireCurrent: () {
            if (!active) throw StateError('changed');
          },
          accountChanges: n,
          accent: accent,
          saveAccent: (_) async {},
          command: (_, _, _, _) async {},
        ),
      ),
    );
    active = false;
    n.notifyListeners();
    result.complete(data());
    await t.pumpAndSettle();
    expect(find.text('연습'), findsNothing);
    await t.pumpWidget(const SizedBox());
    n.dispose();
    accent.dispose();
  });
  test(
    'classification transport never accepts condition edits or foreign routes',
    () {
      final api = SettingsApi(
        Uri.parse('https://example.com'),
        () => throw StateError('must not authenticate'),
        () {},
      );
      for (final route in [
        '/v1/conditions',
        'https://attacker.example/v1/tags',
        '/v1/tags/$id/archive?token=x',
      ]) {
        expect(
          () => api.tagCommand('POST', route, {}, id),
          throwsArgumentError,
        );
      }
    },
  );
}
