import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/sort_sheet.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';

import 'package:song_record/features/songs/song_edit.dart';
import 'package:song_record/features/songs/song_edit_screen.dart';

import 'song_detail_test.dart' as fixture;

Widget app(
  Widget home, {
  AppAccent accent = AppAccent.initial,
  double scale = 1,
  bool reduce = false,
  double keyboard = 0,
}) => MaterialApp(
  theme: AppTheme.dark(accent: accent),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduce,
      viewInsets: EdgeInsets.only(bottom: keyboard),
      padding: const EdgeInsets.only(bottom: 24),
    ),
    child: child!,
  ),
  home: home,
);
void small(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('V46 X02 local search uses NFC, exact whitespace, ASCII fold and literal wildcards', () {
    final s = MySong({
      ...fixture.song(),
      'title': '가 Café %_!',
      'artist': 'ÄBC',
    });
    for (final q in ['가', 'Cafe\u0301', '  %_!  ', ' Äbc ']) {
      expect(s.matches(q), isTrue, reason: q);
    }
    expect(s.matches('äbc'), isFalse);
    expect(normalizeSongText('\u00a0A\u00a0'), 'a');
    expect(normalizeSongText('\ufeffA\ufeff'), '\ufeffa\ufeff');
    expect(compareSortText('é', 'e\u0301'), 0);
    expect(compareSortText('가', '가'), 0);
  });
  testWidgets(
    'X03 narrow large text keeps two views, count and all sort choices usable; cancel preserves state',
    (tester) async {
      small(tester);
      final stream = StreamController<List<MySong>>();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: MySongsScreen(watch: () => stream.stream, onFindSong: () {}),
          ),
          scale: 2,
          reduce: true,
        ),
      );
      stream.add([
        MySong({...fixture.song(), 'title': '긴 곡 제목 ' * 20}),
      ]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('최근 추가순'));
      await tester.tap(find.text('최근 추가순'));
      await tester.pumpAndSettle();
      for (final sort in SongSort.values) {
        expect(find.text(sort.label), findsWidgets);
      }
      await tester.ensureVisible(find.text('취소'));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('최근 추가순'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(stream.close);
    },
  );
  testWidgets(
    'V27 V47 X03 all accents long normal song no recording renders and bottom delete reachable',
    (tester) async {
      small(tester);
      for (final accent in AppAccent.values) {
        final d = MySongDetail({
          'song': {
            ...fixture.song(),
            'title': '긴 제목 ' * 35,
            'artist': '긴 가수 ' * 35,
          },
          'revision': 0,
          'recordings': <Map<String, dynamic>>[],
        });
        await tester.pumpWidget(
          app(
            SongDetailScreen(
              key: ValueKey(accent),
              watch: () => Stream.value(d),
            ),
            accent: accent,
            scale: 2,
            reduce: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('일반 반주'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('일반 반주'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('곡 삭제'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('연결된 녹음이 없어요.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(find.text('곡 삭제'));
        expect(rect.bottom, lessThanOrEqualTo(544));
      }
    },
  );
  testWidgets(
    'X03 return from detail retains original list scroll, query and sort',
    (tester) async {
      final stream = StreamController<List<MySong>>();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: MySongsScreen(
              watch: () => stream.stream,
              onFindSong: () {},
              watchDetail: (id) =>
                  () => Stream.value(
                    MySongDetail({
                      'song': {...fixture.song(), 'id': id},
                      'revision': 0,
                      'recordings': <Map<String, dynamic>>[],
                    }),
                  ),
            ),
          ),
        ),
      );
      stream.add([
        for (var n = 0; n < 40; n++)
          MySong({
            ...fixture.song(),
            'id': fixture.id(n + 100),
            'title': 'Song $n',
          }),
      ]);
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      await tester.drag(find.byType(ListView).first, const Offset(0, -650));
      await tester.pumpAndSettle();
      final before = list.controller!.offset;
      expect(before, greaterThan(0));
      final title = find.text('Song 8');
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      final opened = list.controller!.offset;
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(list.controller!.offset, opened);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(stream.close);
    },
  );
  testWidgets(
    'V46 loading and error never masquerade as empty; retry restores local rows',
    (tester) async {
      final stream = StreamController<List<MySong>>.broadcast();
      var binds = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: MySongsScreen(
              watch: () {
                binds++;
                return stream.stream;
              },
              onFindSong: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('내 곡을 불러오고 있어요.'), findsOneWidget);
      expect(find.text('등록된 내 곡이 없습니다'), findsNothing);
      stream.addError(StateError('local read'));
      await tester.pump();
      expect(find.text('내 곡을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('0곡'), findsNothing);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(binds, 2);
      stream.add([]);
      await tester.pump();
      expect(find.text('0곡'), findsOneWidget);
      expect(find.text('등록된 내 곡이 없습니다'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(stream.close);
    },
  );
  testWidgets(
    'X01 X03 large-font edit with keyboard can cancel all fields without persistence',
    (tester) async {
      small(tester);
      var writes = 0;
      final original = fixture.song();
      final draft = SongEditDraft(
        MySongDetail({
          'song': original,
          'revision': 0,
          'recordings': <Map<String, dynamic>>[],
        }),
      );
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SongEditScreen(
                      draft: draft,
                      prepare: (_) {
                        writes++;
                        return () async {};
                      },
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
          scale: 2,
          reduce: true,
          keyboard: 200,
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '변경 제목');
      await tester.scrollUntilVisible(
        find.text('취소'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(original, fixture.song());
      expect(find.text('열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
