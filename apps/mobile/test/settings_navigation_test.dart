import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/settings_read_screen.dart';
import 'package:song_record/features/settings/settings_screen.dart';

void main() {
  testWidgets(
    'settings routes use supplied live destinations and normal back',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            showDevelopmentTools: false,
            storageBuilder: (_) => const Scaffold(body: Text('현재 계정 보관 상태')),
            classificationBuilder: (_) =>
                const Scaffold(body: Text('현재 계정 분류')),
            importBuilder: (_) => const Scaffold(body: Text('검사된 실제 백업')),
          ),
        ),
      );
      for (final pair in [
        ('보관량과 고정', '현재 계정 보관 상태'),
        ('개인화와 분류 관리', '현재 계정 분류'),
        ('백업 가져오기', '검사된 실제 백업'),
      ]) {
        await tester.tap(find.text(pair.$1));
        await tester.pumpAndSettle();
        expect(find.text(pair.$2), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets('failed state does not show example or stale capacity values', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsReadScreen(
          title: '보관량',
          requireCurrent: () {},
          load: () async {
            if (fail) throw const SettingsUnavailable();
            return [('사용량', '197')];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('197'), findsOneWidget);
    fail = true;
    await tester.tap(find.text('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('197'), findsNothing);
    expect(find.textContaining('읽지 못했어요'), findsOneWidget);
  });
  testWidgets('account switch hides finished values and late old response', (
    tester,
  ) async {
    final notifier = ChangeNotifier(),
        response = Completer<List<(String, String)>>();
    var active = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsReadScreen(
          title: '분류',
          accountChanges: notifier,
          requireCurrent: () {
            if (!active) throw StateError('switched');
          },
          load: () => response.future,
        ),
      ),
    );
    active = false;
    notifier.notifyListeners();
    response.complete([('태그', '다른 계정에 보이면 안 되는 값')]);
    await tester.pumpAndSettle();
    expect(find.text('다른 계정에 보이면 안 되는 값'), findsNothing);
    expect(find.textContaining('읽지 못했어요'), findsOneWidget);
    notifier.dispose();
  });
  test('settings transport rejects nonlocal plaintext and credential URLs', () {
    for (final origin in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com/?secret=1',
    ]) {
      expect(
        () => SettingsApi(
          Uri.parse(origin),
          () => throw StateError('must not authenticate'),
          () {},
        ),
        throwsArgumentError,
      );
    }
  });
  testWidgets('replacing the account loader clears previous visible values', (
    tester,
  ) async {
    void guard() {}
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsReadScreen(
          title: '보관량',
          requireCurrent: guard,
          load: () async => [('이전 계정', 'old-private-value')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final next = Completer<List<(String, String)>>();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsReadScreen(
          title: '보관량',
          requireCurrent: guard,
          load: () => next.future,
        ),
      ),
    );
    expect(find.text('old-private-value'), findsNothing);
    next.complete([('현재 계정', 'new-value')]);
    await tester.pumpAndSettle();
    expect(find.text('new-value'), findsOneWidget);
  });
  test('unknown settings path cannot request account credentials', () async {
    var authenticated = false;
    final api = SettingsApi(Uri.parse('https://example.com'), () async {
      authenticated = true;
      throw StateError('no network allowed');
    }, () {});
    await expectLater(api.get('/foreign-route'), throwsArgumentError);
    expect(authenticated, false);
  });
}
