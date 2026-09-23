import 'package:flutter/material.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';
import 'package:song_record/core/widgets/sort_sheet.dart';
import 'package:song_record/core/widgets/tier_picker.dart';
import 'package:song_record/core/widgets/version_picker.dart';

void main() => runApp(const SelectionSheetsPreview());

class SelectionSheetsPreview extends StatefulWidget {
  const SelectionSheetsPreview({super.key});

  @override
  State<SelectionSheetsPreview> createState() => _SelectionSheetsPreviewState();
}

// Preview-only data. Song and recording edits deliberately remain independent.
class _SongSample {
  _SongSample(
    this.id,
    this.title,
    this.artist,
    this.addedDay,
    this.recordedDay,
    this.tier,
    this.version,
  );
  final int id;
  final String title;
  final String artist;
  final int addedDay;
  final int? recordedDay;
  SongTier? tier;
  VersionCode version;
}

class _RecordingSample {
  _RecordingSample(
    this.id,
    this.title,
    this.artist,
    this.day,
    this.tier,
    this.version,
  );
  final int id;
  final String title;
  final String artist;
  final int day;
  RecordingTier? tier;
  VersionCode version;
}

class _SelectionSheetsPreviewState extends State<SelectionSheetsPreview> {
  SongSort songSort = SongSort.recentlyAdded;
  RecordingSort recordingSort = RecordingSort.newest;
  AppAccent accent = AppAccent.initial;
  String lastAction = '정렬을 바꾸거나 각 항목의 티어·버전을 눌러 보세요.';
  final songs = [
    _SongSample(1, '바람 연습곡', '가람', 23, 21, SongTier.b, VersionCode.normal),
    _SongSample(2, '가을 연습곡', '하늘', 21, 23, SongTier.a, VersionCode.mr),
    _SongSample(3, '노을 연습곡', '다온', 22, null, null, VersionCode.live),
  ];
  final recordings = [
    _RecordingSample(1, '가을 연습곡', '하늘', 23, RecordingTier.c, VersionCode.mr),
    _RecordingSample(
      2,
      '바람 연습곡',
      '가람',
      21,
      RecordingTier.a,
      VersionCode.normal,
    ),
    _RecordingSample(3, '바람 연습곡', '가람', 20, null, VersionCode.live),
  ];

  int compareSongs(_SongSample a, _SongSample b) {
    final compared = switch (songSort) {
      SongSort.recentlyAdded => b.addedDay.compareTo(a.addedDay),
      SongSort.recentlyRecorded => (b.recordedDay ?? -1).compareTo(
        a.recordedDay ?? -1,
      ),
      SongSort.tier => (a.tier?.index ?? 5).compareTo(b.tier?.index ?? 5),
      SongSort.title => compareSortText(a.title, b.title),
      SongSort.artist => compareSortText(a.artist, b.artist),
    };
    if (compared != 0) return compared;
    final added = b.addedDay.compareTo(a.addedDay);
    return added != 0 ? added : a.id.compareTo(b.id);
  }

  int compareRecordings(_RecordingSample a, _RecordingSample b) {
    final compared = switch (recordingSort) {
      RecordingSort.newest => b.day.compareTo(a.day),
      RecordingSort.oldest => a.day.compareTo(b.day),
      RecordingSort.title => compareSortText(a.title, b.title),
      RecordingSort.tier => (a.tier?.index ?? 5).compareTo(b.tier?.index ?? 5),
    };
    if (compared != 0) return compared;
    final time = b.day.compareTo(a.day);
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  Future<void> choose<T>(
    Future<SelectionResult<T>?> pending,
    void Function(T) update,
    String message,
  ) async {
    final result = await pending;
    if (!mounted) return;
    setState(() {
      if (result == null) {
        lastAction = '취소 · 기존 값을 유지했어요.';
      } else {
        update(result.value);
        lastAction = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderedSongs = [...songs]..sort(compareSongs);
    final orderedRecordings = [...recordings]..sort(compareRecordings);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(accent: accent),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('공통 선택창 미리보기')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('샘플 곡 3개·녹음 3개로 확인해 보세요. 변경은 이 화면에서만 유지돼요.'),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in AppAccent.values)
                    ChoiceChip(
                      label: Text(value.label),
                      selected: value == accent,
                      onSelected: (_) => setState(() => accent = value),
                    ),
                ],
              ),
              Semantics(liveRegion: true, child: Text(lastAction)),
              const SizedBox(height: 20),
              const Text('내 곡 · 3곡', style: AppTypography.detailTitle),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('song-sort'),
                  icon: const Icon(Icons.sort),
                  label: Text(songSort.label),
                  onPressed: () => choose(
                    SortSheet.songs(context: context, selected: songSort),
                    (value) => songSort = value,
                    '내 곡 목록의 순서를 바꿨어요.',
                  ),
                ),
              ),
              for (final song in orderedSongs)
                sampleCard(
                  key: ValueKey('song-${song.id}'),
                  title: song.title,
                  subtitle: '${song.artist} · 곡 ${song.id}',
                  date:
                      '추가 9/${song.addedDay} · 최근 녹음 ${song.recordedDay == null ? "없음" : "9/${song.recordedDay}"}',
                  tierLabel: '곡 티어 · ${formatSongTier(song.tier)}',
                  version: song.version,
                  onTier: () => choose(
                    TierPicker.song(context: context, selected: song.tier),
                    (value) => song.tier = value,
                    '${song.title}의 곡 티어를 바꿨어요.',
                  ),
                  onVersion: () => choose(
                    VersionPicker.show(
                      context: context,
                      selected: song.version,
                    ),
                    (value) => song.version = value,
                    '${song.title}의 곡 버전을 바꿨어요. 기존 녹음 버전은 유지돼요.',
                  ),
                ),
              const SizedBox(height: 20),
              const Text('녹음 · 3개', style: AppTypography.detailTitle),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('recording-sort'),
                  icon: const Icon(Icons.sort),
                  label: Text(recordingSort.label),
                  onPressed: () => choose(
                    SortSheet.recordings(
                      context: context,
                      selected: recordingSort,
                    ),
                    (value) => recordingSort = value,
                    '녹음 목록의 순서를 바꿨어요.',
                  ),
                ),
              ),
              for (final recording in orderedRecordings)
                sampleCard(
                  key: ValueKey('recording-${recording.id}'),
                  title: recording.title,
                  subtitle: '${recording.artist} · 녹음 ${recording.id}',
                  date: '녹음 9/${recording.day} · 샘플 정보만 있음',
                  tierLabel: '녹음 티어 · ${formatRecordingTier(recording.tier)}',
                  version: recording.version,
                  onTier: () => choose(
                    TierPicker.recording(
                      context: context,
                      selected: recording.tier,
                    ),
                    (value) => recording.tier = value,
                    '녹음 ${recording.id}의 티어를 바꿨어요.',
                  ),
                  onVersion: () => choose(
                    VersionPicker.show(
                      context: context,
                      selected: recording.version,
                    ),
                    (value) => recording.version = value,
                    '녹음 ${recording.id}의 버전을 바꿨어요.',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sampleCard({
    required Key key,
    required String title,
    required String subtitle,
    required String date,
    required String tierLabel,
    required VersionCode version,
    required VoidCallback onTier,
    required VoidCallback onVersion,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTypography.songTitle),
            Text(subtitle, style: AppTypography.supporting),
            const SizedBox(height: 8),
            Text(date, style: AppTypography.supporting),
            Wrap(
              spacing: 8,
              children: [
                TextButton(onPressed: onTier, child: Text(tierLabel)),
                TextButton(
                  onPressed: onVersion,
                  child: Text('버전 · ${formatVersionCode(version)}'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
