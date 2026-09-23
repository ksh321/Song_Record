import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/playlist_song_picker.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';

import '../tool/preview_song_discovery.dart';

final song = RegisteredSongViewData(
  id: SongId('00000000-0000-4000-8000-000000000001'),
  title: '아침 노래', artist: 'Sample Band', version: VersionCode.normal,
);

Future<void> show(WidgetTester tester, Widget child, {bool reduceMotion = false}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('새 곡 찾기는 같은 크기의 두 카드와 목록 문맥을 반환한다', (tester) async {
    SongDiscoveryResult? result;
    await show(tester, Builder(builder: (context) => TextButton(
      onPressed: () async {
        result = await showSongDiscoverySheet(context: context, playlistId: 'list-1', playlistTitle: '연습 목록');
      },
      child: const Text('열기'),
    )));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final chart = find.ancestor(of: find.text('인기 차트'), matching: find.byType(InkWell)).first;
    final search = find.ancestor(of: find.text('검색'), matching: find.byType(InkWell)).first;
    expect(tester.getSize(chart), tester.getSize(search));
    expect(tester.getSize(chart).height, greaterThanOrEqualTo(156));
    expect(tester.getTopLeft(chart).dy, tester.getTopLeft(search).dy);
    expect(tester.getTopLeft(search).dx - tester.getTopRight(chart).dx, 12);
    expect(find.text('내 곡에서 선택'), findsOneWidget);
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(result?.destination, SongDiscoveryDestination.search);
    expect(result?.playlistId, 'list-1');
  });

  testWidgets('목록 밖에서는 내 곡 선택이 없고 취소와 뒤로가기는 null이다', (tester) async {
    final results = <SongDiscoveryResult?>[];
    await show(tester, Builder(builder: (context) => TextButton(
      onPressed: () async { results.add(await showSongDiscoverySheet(context: context)); },
      child: const Text('열기'),
    )));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('내 곡에서 선택'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(results, [null, null]);
  });

  testWidgets('작은 화면 큰 글자에서도 2열을 유지하고 취소에 접근한다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showSongDiscoverySheet(context: context, playlistId: 'list-1'),
        child: const Text('열기'),
      ))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('새 곡 찾기'), findsNothing);
  });

  testWidgets('로딩, 빈 결과, 통신 실패, 대기가 구분되고 재시도한다', (tester) async {
    var retries = 0;
    for (final phase in ContentPhase.values) {
      await show(tester, ContentState(
        phase: phase, title: phase.name,
        onRetry: phase == ContentPhase.error ? () => retries++ : null,
      ));
      expect(find.text(phase.name), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), phase == ContentPhase.loading ? findsOneWidget : findsNothing);
      if (phase == ContentPhase.error) {
        await tester.tap(find.text('다시 시도'));
        expect(retries, 1);
      } else { expect(find.text('다시 시도'), findsNothing); }
    }
    await show(tester, const ContentState(phase: ContentPhase.loading, title: '로딩'), reduceMotion: true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('로딩'), findsOneWidget);
  });

  Widget picker({Set<SongId> included = const {}, required Future<void> Function(String, SongId) add, SongListPhase phase = SongListPhase.ready}) => PlaylistSongPicker(
    playlistId: 'list-1', playlistTitle: '연습 목록', songs: [song], includedSongIds: included,
    onAdd: add, onDiscover: () {}, onDone: () {}, phase: phase,
  );

  testWidgets('내 곡 검색은 공백과 영문 대소문자를 정리하고 중복 추가를 막는다', (tester) async {
    final calls = <String>[];
    await show(tester, picker(add: (list, id) async { calls.add('$list/${id.value}'); }));
    await tester.enterText(find.byType(TextField), '  SAMPLE  ');
    await tester.pump();
    expect(find.text('아침 노래'), findsOneWidget);
    await tester.tap(find.text('아침 노래'));
    await tester.pumpAndSettle();
    expect(find.text('추가됨'), findsOneWidget);
    await tester.tap(find.text('아침 노래'));
    await tester.pump();
    expect(calls, ['list-1/${song.id.value}']);
    await tester.enterText(find.byType(TextField), '없는 곡');
    await tester.pump();
    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
  });

  testWidgets('이미 담긴 곡은 처음부터 추가 불가다', (tester) async {
    var calls = 0;
    await show(tester, picker(included: {song.id}, add: (_, _) async { calls++; }));
    await tester.tap(find.text('아침 노래'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('추가됨'), findsOneWidget);
  });

  testWidgets('진행 중 연타를 막고 실패한 추가만 재시도한다', (tester) async {
    var calls = 0;
    final first = Completer<void>();
    await show(tester, picker(add: (_, _) { calls++; return calls == 1 ? first.future : Future<void>.value(); }));
    await tester.tap(find.text('아침 노래'));
    await tester.pump();
    await tester.ensureVisible(find.text('아침 노래'));
    await tester.tap(find.text('아침 노래'));
    expect(calls, 1);
    first.completeError(StateError('sample failure'));
    await tester.pumpAndSettle();
    expect(find.text('곡을 추가하지 못했어요.'), findsOneWidget);
    expect(find.text('추가됨'), findsNothing);
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('추가됨'), findsOneWidget);
  });

  testWidgets('불러오기 실패를 빈 목록으로 표시하지 않는다', (tester) async {
    await show(tester, picker(phase: SongListPhase.error, add: (_, _) async {}));
    expect(find.text('내 곡을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('아침 노래'), findsNothing);
    expect(find.text('등록된 내 곡이 없습니다'), findsNothing);
  });

  testWidgets('다른 목록으로 바뀐 뒤 이전 요청 완료가 새 목록을 바꾸지 않는다', (tester) async {
    final request = Completer<void>();
    await show(tester, picker(add: (_, _) => request.future));
    await tester.tap(find.text('아침 노래'));
    await tester.pump();
    await show(tester, PlaylistSongPicker(
      playlistId: 'list-2', playlistTitle: '다른 목록', songs: [song], includedSongIds: const {},
      onAdd: (_, _) async {}, onDiscover: () {}, onDone: () {},
    ));
    request.complete();
    await tester.pumpAndSettle();
    expect(find.text('다른 목록'), findsOneWidget);
    expect(find.text('추가됨'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('목록에서 내 곡 추가 후 완료하면 원래 목록에 돌아온다', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: const DiscoveryPreview()));
    await tester.tap(find.text('오늘 부를 곡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('곡 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 곡에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아침 노래'));
    await tester.pumpAndSettle();
    expect(find.text('추가됨'), findsOneWidget);
    await tester.ensureVisible(find.text('완료'));
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 부를 곡'), findsOneWidget);
    expect(find.text('메모리 샘플 · 1곡'), findsOneWidget);
    expect(find.text('아침 노래'), findsOneWidget);
  });
}
