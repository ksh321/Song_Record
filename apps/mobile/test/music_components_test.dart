import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/recording_snapshot.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/recording_roles_card.dart';
import 'package:song_record/core/widgets/recording_row.dart';
import 'package:song_record/core/widgets/song_row.dart';
import 'package:song_record/core/widgets/song_summary.dart';

void main() {
  final songId = SongId('00000000-0000-4000-8000-000000000001');
  final recordingId = RecordingId('00000000-0000-4000-8000-000000000002');
  RegisteredSongViewData song({String title = '등록곡 제목'}) =>
      RegisteredSongViewData(
        id: songId,
        title: title,
        artist: '등록 가수',
        version: VersionCode.normal,
        tjNumber: TjNumber('00123'),
        musicalKey: MusicalKey.original,
        tier: SongTier.b,
        note: '다음 연습에서 확인할 메모',
      );
  CandidateSongViewData candidate({CatalogBrand brand = CatalogBrand.tj}) =>
      CandidateSongViewData(
        brand: brand,
        number: '00123',
        title: '후보 제목 (LIVE)',
        artist: '후보 가수',
      );
  RecordingViewData recording({
    RecordingFileAvailability availability =
        RecordingFileAvailability.metadataOnly,
  }) => RecordingViewData(
    snapshot: RecordingSnapshot(
      id: recordingId,
      songId: songId,
      title: '당시 제목',
      artist: '당시 가수',
      key: MusicalKey(mode: KeyMode.male, shift: 0),
      version: VersionCode.live,
      note: '',
      recordedAt: DateTime.utc(2026, 9, 22, 16, 5),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    ),
    duration: const Duration(minutes: 3, seconds: 7),
    tier: RecordingTier.c,
    fileAvailability: availability,
  );
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    AppAccent accent = AppAccent.blue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(accent: accent),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('등록곡은 기본 버전도 표시하고 번호는 숨기며 추가된 항목을 막는다', (tester) async {
    var taps = 0;
    await show(tester, SongRow.registered(song: song(), onTap: () => taps++));
    expect(find.text('등록 가수 · 일반 반주'), findsOneWidget);
    expect(find.text('원키'), findsOneWidget);
    expect(find.textContaining('00123'), findsNothing);
    await tester.tap(find.text('등록곡 제목'));
    expect(taps, 1);
    await show(
      tester,
      SongRow.registered(song: song(), alreadyAdded: true, onTap: () => taps++),
    );
    expect(find.text('추가됨'), findsOneWidget);
    await tester.tap(find.text('등록곡 제목'));
    expect(taps, 1);
  });

  testWidgets('후보는 개인 값 없이 출처와 순위를 표시하고 플리에서는 번호를 숨긴다', (tester) async {
    for (final placement in CandidatePlacement.values) {
      await show(
        tester,
        SongRow.candidate(
          candidate: candidate(),
          placement: placement,
          rank: placement == CandidatePlacement.chart ? 2 : null,
        ),
      );
      expect(find.text('후보 제목 (LIVE)'), findsOneWidget);
      expect(find.text('일반 반주'), findsNothing);
      expect(find.byType(MusicalKeyBadge), findsNothing);
      expect(find.text('미정'), findsNothing);
      expect(
        find.text('TJ 00123'),
        placement == CandidatePlacement.playlist
            ? findsNothing
            : findsOneWidget,
      );
      if (placement == CandidatePlacement.chart) {
        expect(find.text('2'), findsOneWidget);
      }
      if (placement == CandidatePlacement.playlist) {
        expect(find.text('내 곡 미등록'), findsOneWidget);
      }
    }
    expect(
      () => SongRow.candidate(
        candidate: candidate(brand: CatalogBrand.ky),
        placement: CandidatePlacement.playlist,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('녹음은 스냅샷·저장 시각·파일 상태를 표시하고 파일 없어도 상세를 연다', (tester) async {
    var taps = 0;
    for (final availability in RecordingFileAvailability.values) {
      await show(
        tester,
        RecordingRow(
          recording: recording(availability: availability),
          onTap: () => taps++,
        ),
      );
      expect(find.text('당시 제목'), findsOneWidget);
      expect(find.text('당시 가수'), findsOneWidget);
      expect(find.text('2026.09.23 01:05 · 03:07'), findsOneWidget);
      expect(find.text('LIVE · 남 0 · 티어 C'), findsOneWidget);
      expect(find.text(availability.label), findsOneWidget);
      await tester.tap(find.text('당시 제목'));
    }
    expect(taps, RecordingFileAvailability.values.length);
  });

  testWidgets('곡 요약은 번호·아쉬운 점을 표시하고 곡 수정 버튼만 편집한다', (tester) async {
    var edits = 0;
    await show(tester, SongSummary(song: song(), onEdit: () => edits++));
    expect(find.text('등록 가수 · TJ 00123'), findsOneWidget);
    expect(find.text('다음 연습에서 확인할 메모'), findsOneWidget);
    await tester.tap(find.text('일반 반주'));
    expect(edits, 0);
    await tester.tap(find.text('곡 수정'));
    expect(edits, 1);
    await show(
      tester,
      SongSummary(
        song: RegisteredSongViewData(
          id: songId,
          title: '수동곡',
          artist: '가수',
          version: VersionCode.mr,
        ),
      ),
    );
    expect(find.text('가수 · TJ 번호 없음'), findsOneWidget);
    expect(find.text('미정'), findsNWidgets(2));
    expect(find.text('아직 작성하지 않았어요.'), findsOneWidget);
  });

  testWidgets('역할 세 개를 항상 보이며 같은 녹음은 한 개로 세고 상세 콜백을 전달한다', (tester) async {
    var edits = 0;
    RecordingId? opened;
    await show(
      tester,
      RecordingRolesCard(
        songId: songId,
        selection: RecordingSelection(
          representative: recordingId,
          latest: recordingId,
          lowestTier: recordingId,
        ),
        recordings: {recordingId: recording()},
        onChooseRepresentative: () => edits++,
        onOpenRecording: (id) => opened = id,
      ),
    );
    expect(find.text('자동 보관 대상 1개'), findsOneWidget);
    for (final label in ['대표 녹음', '최신 녹음', '최저 티어 녹음']) {
      expect(find.text(label), findsOneWidget);
    }
    // A metadata-only record can still be a target. No false "stored" claim.
    expect(find.text('서버에 파일 있음'), findsNothing);
    await tester.tap(find.text('변경'));
    expect(edits, 1);
    await tester.tap(find.text('최신 녹음'));
    expect(opened, recordingId);
    await tester.tap(find.text('자동 보관 기준'));
    await tester.pumpAndSettle();
    expect(find.textContaining('파일이 서버에 있다는 뜻은 아니에요'), findsOneWidget);
    expect(find.text('대표 녹음'), findsOneWidget);
    await show(
      tester,
      RecordingRolesCard(
        songId: songId,
        selection: const RecordingSelection(),
        recordings: const {},
      ),
    );
    expect(find.text('자동 보관 대상 0개'), findsOneWidget);
    expect(find.text('미지정 · 직접 골라 주세요'), findsOneWidget);
    expect(find.text('녹음 없음'), findsOneWidget);
    expect(find.text('평가된 녹음 없음'), findsOneWidget);
  });

  test('역할 표시에서 다른 곡이나 누락된 녹음 데이터를 거절한다', () {
    final selection = RecordingSelection(latest: recordingId);
    expect(
      () => RecordingRolesCard(
        songId: songId,
        selection: selection,
        recordings: const {},
      ),
      throwsArgumentError,
    );
    expect(
      () => RecordingRolesCard(
        songId: SongId('00000000-0000-4000-8000-000000000099'),
        selection: selection,
        recordings: {recordingId: recording()},
      ),
      throwsArgumentError,
    );
  });

  testWidgets('320 폭과 큰 글꼴에서 긴 제목과 요약이 잘리거나 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longSong = song(title: '긴 제목을 끝까지 읽을 수 있도록 여러 줄로 표시하는 샘플 곡입니다');
    for (final scale in [1.0, 2.0, 3.0]) {
      await show(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SongRow.registered(song: longSong),
              SongRow.candidate(
                candidate: candidate(),
                placement: CandidatePlacement.playlist,
              ),
              RecordingRow(recording: recording()),
              SongSummary(song: longSong),
              RecordingRolesCard(
                songId: songId,
                selection: RecordingSelection(latest: recordingId),
                recordings: {recordingId: recording()},
              ),
            ],
          ),
        ),
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(SongRow).first).height,
        greaterThanOrEqualTo(AppDimensions.compactSongRowMinHeight),
      );
      expect(
        tester.getSize(find.byType(RecordingRow)).height,
        greaterThanOrEqualTo(AppDimensions.recordRowMinHeight),
      );
      expect(find.text(longSong.title), findsNWidgets(2));
    }
  });

  testWidgets('키 배지 색과 텍스트는 강조색을 바꿔도 유지한다', (tester) async {
    for (final accent in AppAccent.values) {
      await show(
        tester,
        MusicalKeyBadge(value: MusicalKey(mode: KeyMode.female, shift: 1)),
        accent: accent,
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(MusicalKeyBadge),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        AppColors.keyFemaleBackground,
      );
      expect(find.text('여 +1'), findsOneWidget);
    }
  });
}
