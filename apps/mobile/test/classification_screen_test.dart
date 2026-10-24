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
      {
        'id':
            '00000000-0000-4000-8000-${['VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'].indexOf(c).toString().padLeft(12, '0')}',
        'code': c,
        'name': c,
        'revision': 1,
        'archived_at': null,
      },
  ],
);
void main() {
  testWidgets(
    'device accents persist and legacy white migrates to the default',
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
        expect(
          await preferences.read(),
          accent == AppAccent.white ? AppAccent.initial : accent,
        );
      }
      expect(AppAccent.values, hasLength(8));
      expect(methods.toSet(), {'readAccent', 'writeAccent'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceAccentPreferences.channel, null);
    },
  );
  testWidgets(
    'tag removal cancellation sends nothing; confirmed archive hides only the selection row',
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
      await t.tap(find.text('태그 관리'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('태그 삭제'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(commands, isEmpty);
      await t.tap(find.byTooltip('태그 삭제'));
      await t.pumpAndSettle();
      await t.tap(find.text('삭제'));
      await t.pumpAndSettle();
      expect(commands.single, {
        'method': 'POST',
        'path': '/v1/tags/$id/archive',
        'body': {'base_revision': 7},
      });
      expect(find.text('연습'), findsNothing);
      expect(find.text('등록한 태그가 없어요.'), findsOneWidget);
      expect(find.byTooltip('이름 변경'), findsNothing);
      await t.tap(find.byTooltip('이전 화면'));
      await t.pumpAndSettle();
      await t.tap(find.text('컨디션 관리'));
      await t.pumpAndSettle();
      expect(find.byTooltip('컨디션 이름 변경'), findsWidgets);
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
    await t.tap(find.text('태그 관리'));
    await t.pumpAndSettle();
    final raw = List.filled(51, '😀').join();
    await t.enterText(find.byType(TextField), raw);
    await t.tap(find.text('추가'));
    await t.pumpAndSettle();
    expect(sent, 0);
    expect(find.textContaining('1~50자로'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, raw);
    await t.pumpWidget(const SizedBox());
    accent.dispose();
  });
  testWidgets(
    'custom condition create and rename use owned endpoints and latest revision',
    (t) async {
      final accent = ValueNotifier(AppAccent.blue);
      var conditions = <Map<String, dynamic>>[];
      final sent = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: ClassificationScreen(
            load: () async =>
                (tags: <Map<String, dynamic>>[], conditions: conditions),
            requireCurrent: () {},
            accent: accent,
            saveAccent: (_) async {},
            command: (method, path, body, op) async {
              sent.add('$method $path');
              if (method == 'POST') {
                conditions = [
                  {
                    'id': body['id'],
                    'code': body['id'],
                    'name': body['name'],
                    'revision': 1,
                    'archived_at': null,
                  },
                ];
              } else {
                expect(body['base_revision'], 1);
                conditions = [
                  {...conditions.single, 'name': body['name'], 'revision': 2},
                ];
              }
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('컨디션 관리'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '목이 편함');
      await t.tap(find.text('추가'));
      await t.pumpAndSettle();
      expect(find.text('목이 편함'), findsOneWidget);
      await t.tap(find.byTooltip('컨디션 이름 변경'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '목 상태 좋음');
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();
      expect(find.text('목 상태 좋음'), findsOneWidget);
      expect(sent.first, 'POST /v1/conditions');
      expect(sent.last, 'PATCH /v1/conditions/${conditions.single['id']}');
      await t.pumpWidget(const SizedBox());
      accent.dispose();
    },
  );
  for (final menu in ['태그 관리', '컨디션 관리']) {
    testWidgets('$menu keyboard rebuild keeps the loaded list and input', (
      t,
    ) async {
      final accent = ValueNotifier(AppAccent.blue);
      var loads = 0;
      Widget app(double bottom) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: bottom)),
          child: Builder(
            builder: (context) {
              MediaQuery.viewInsetsOf(context);
              return ClassificationScreen(
                key: const ValueKey('same-account'),
                load: () async {
                  loads++;
                  if (loads > 1) throw StateError('unexpected layout reload');
                  return data();
                },
                requireCurrent: () {},
                accent: accent,
                saveAccent: (_) async {},
                command: (_, _, _, _) async {},
              );
            },
          ),
        ),
      );
      await t.pumpWidget(app(0));
      await t.pumpAndSettle();
      await t.tap(find.text(menu));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '입력 중');
      for (final inset in [80.0, 160.0, 240.0, 0.0, 240.0]) {
        await t.pumpWidget(app(inset));
        await t.pumpAndSettle();
      }
      expect(loads, 1);
      expect(find.text('분류 정보를 확인하지 못했어요. 새로고침해 주세요.'), findsNothing);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '입력 중',
      );
      await t.pumpWidget(const SizedBox());
      accent.dispose();
    });
  }

  testWidgets('account-scoped key discards the old list and late response', (
    t,
  ) async {
    final accent = ValueNotifier(AppAccent.blue);
    final first = Completer<ClassificationData>();
    Widget app(String account, Future<ClassificationData> Function() load) =>
        MaterialApp(
          home: ClassificationScreen(
            key: ValueKey(account),
            load: load,
            requireCurrent: () {},
            accent: accent,
            saveAccent: (_) async {},
            command: (_, _, _, _) async {},
          ),
        );
    await t.pumpWidget(app('old', () => first.future));
    await t.pumpWidget(
      app(
        'new',
        () async => (
          tags: <Map<String, dynamic>>[],
          conditions: <Map<String, dynamic>>[],
        ),
      ),
    );
    await t.pumpAndSettle();
    first.complete(data());
    await t.pumpAndSettle();
    await t.tap(find.text('태그 관리'));
    await t.pumpAndSettle();
    expect(find.text('연습'), findsNothing);
    expect(find.text('등록한 태그가 없어요.'), findsOneWidget);
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
    await t.tap(find.text('태그 관리'));
    await t.pump();
    active = false;
    n.notifyListeners();
    result.complete(data());
    await t.pumpAndSettle();
    expect(find.text('연습'), findsNothing);
    await t.pumpWidget(const SizedBox());
    n.dispose();
    accent.dispose();
  });
  testWidgets('account switch clears an unsent inline classification name', (
    t,
  ) async {
    final n = ChangeNotifier(), accent = ValueNotifier(AppAccent.blue);
    var active = true, sent = 0;
    await t.pumpWidget(
      MaterialApp(
        home: ClassificationScreen(
          load: () async => data(),
          requireCurrent: () {
            if (!active) throw StateError('changed');
          },
          accountChanges: n,
          accent: accent,
          saveAccent: (_) async {},
          command: (_, _, _, _) async {
            sent++;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('태그 관리'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '보내지 않은 이름');
    active = false;
    n.notifyListeners();
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('연습'), findsNothing);
    expect(sent, 0);
    await t.pumpWidget(const SizedBox());
    n.dispose();
    accent.dispose();
  });
  test('classification transport rejects foreign or malformed routes', () {
    final api = SettingsApi(
      Uri.parse('https://example.com'),
      () => throw StateError('must not authenticate'),
      () {},
    );
    for (final route in [
      '/v1/conditions/invalid',
      'https://attacker.example/v1/tags',
      '/v1/tags/$id/archive?token=x',
    ]) {
      expect(() => api.tagCommand('POST', route, {}, id), throwsArgumentError);
    }
  });
}
