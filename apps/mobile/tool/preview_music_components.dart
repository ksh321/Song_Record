import 'package:flutter/material.dart';
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

void main() => runApp(const MusicComponentsPreview());

/// Standalone samples; no native recorder, DB, network or real mutations.
class MusicComponentsPreview extends StatefulWidget {
  const MusicComponentsPreview({super.key});

  @override
  State<MusicComponentsPreview> createState() => _MusicComponentsPreviewState();
}

class _MusicComponentsPreviewState extends State<MusicComponentsPreview> {
  AppAccent _accent = AppAccent.initial;
  bool _largeText = false;
  final _song = RegisteredSongViewData(
    id: SongId('00000000-0000-4000-8000-000000000001'),
    title: '아주 긴 곡 제목이 여러 줄이 되어도 끝까지 확인할 수 있는 연습곡',
    artist: '샘플 가수',
    version: VersionCode.mr,
    tjNumber: TjNumber('00123'),
    musicalKey: MusicalKey(mode: KeyMode.female, shift: 1),
    tier: SongTier.b,
    note: '후반부 호흡을 천천히 나눠서 연습하기. 미리보기용 메모입니다.',
  );

  late final _recording = RecordingViewData(
    snapshot: RecordingSnapshot(
      id: RecordingId('00000000-0000-4000-8000-000000000002'),
      songId: _song.id,
      title: '녹음할 당시의 제목',
      artist: '녹음할 당시의 가수',
      key: MusicalKey.original,
      version: VersionCode.live,
      note: '',
      recordedAt: DateTime.utc(2026, 9, 22, 13, 30),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    ),
    duration: const Duration(minutes: 3, seconds: 27),
    fileAvailability: RecordingFileAvailability.metadataOnly,
    tier: RecordingTier.c,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(accent: _accent),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: _largeText
              ? const TextScaler.linear(2)
              : MediaQuery.textScalerOf(context),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          void report(String action) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('미리보기: $action · 실제 데이터는 변경하지 않아요.')),
            );
          }

          final manual = RegisteredSongViewData(
            id: SongId('00000000-0000-4000-8000-000000000003'),
            title: '직접 등록한 샘플 곡',
            artist: '샘플 가수',
            version: VersionCode.normal,
          );
          final candidate = CandidateSongViewData(
            brand: CatalogBrand.tj,
            number: '00123',
            title: '후보 곡 (LIVE)',
            artist: '후보 가수',
          );
          return Scaffold(
            appBar: AppBar(title: const Text('행·요약 미리보기')),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const Text('P05-04 검증용 샘플 · 실제 곡·녹음이 아닙니다.'),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final accent in AppAccent.values)
                        ChoiceChip(
                          label: Text(accent.label),
                          selected: _accent == accent,
                          onSelected: (_) => setState(() => _accent = accent),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('큰 글자 2배 미리보기'),
                    value: _largeText,
                    onChanged: (value) => setState(() => _largeText = value),
                  ),
                  _heading('등록곡'),
                  SongRow.registered(
                    song: _song,
                    onTap: () => report('등록곡 열기'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SongRow.registered(
                    song: manual,
                    onTap: () => report('직접 등록곡 열기'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SongRow.registered(
                    song: _song,
                    alreadyAdded: true,
                    onTap: () => report('이 동작은 실행되면 안 됩니다'),
                  ),
                  _heading('검색·차트·플레이리스트 후보'),
                  SongRow.candidate(
                    candidate: candidate,
                    placement: CandidatePlacement.search,
                    onTap: () => report('후보 동작 열기'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SongRow.candidate(
                    candidate: candidate,
                    placement: CandidatePlacement.chart,
                    rank: 1,
                    onTap: () => report('차트 후보 열기'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SongRow.candidate(
                    candidate: candidate,
                    placement: CandidatePlacement.playlist,
                    onTap: () => report('미등록 TJ 후보 열기'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SongRow.candidate(
                    candidate: CandidateSongViewData(
                      brand: CatalogBrand.ky,
                      number: '00456',
                      title: '금영 샘플 곡',
                      artist: '후보 가수',
                    ),
                    placement: CandidatePlacement.search,
                    onTap: () => report('TJ에서 이 곡 찾기 진입'),
                  ),
                  _heading('녹음 · 실제 파일 상태'),
                  for (final availability
                      in RecordingFileAvailability.values) ...[
                    RecordingRow(
                      recording: RecordingViewData(
                        snapshot: _recording.snapshot,
                        duration: _recording.duration,
                        tier: _recording.tier,
                        fileAvailability: availability,
                      ),
                      onTap: () => report('녹음 상세 열기'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _heading('곡 요약 · 읽기 전용 값'),
                  SongSummary(song: _song, onEdit: () => report('곡 수정 진입')),
                  const SizedBox(height: AppSpacing.lg),
                  SongSummary(
                    song: manual,
                    onEdit: () => report('직접 등록곡 수정 진입'),
                  ),
                  _heading('같은 녹음이 세 역할 · 대상은 1개'),
                  RecordingRolesCard(
                    songId: _song.id,
                    selection: RecordingSelection(
                      representative: _recording.id,
                      latest: _recording.id,
                      lowestTier: _recording.id,
                    ),
                    recordings: {_recording.id: _recording},
                    onChooseRepresentative: () => report('대표 녹음 변경'),
                    onOpenRecording: (_) => report('역할의 녹음 상세 열기'),
                  ),
                  _heading('녹음이 없는 경우'),
                  RecordingRolesCard(
                    songId: manual.id,
                    selection: const RecordingSelection(),
                    recordings: const {},
                    onChooseRepresentative: () => report('대표 녹음 지정'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(text, style: AppTypography.songTitle),
  );
}
