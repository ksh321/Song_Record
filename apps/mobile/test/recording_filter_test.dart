import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/features/recorder/recording_filter.dart';
import 'package:song_record/features/recorder/recording_list.dart';

Map<String, dynamic> record(String id, String time) => {
  'id': id,
  'title_snapshot': '곡',
  'artist_snapshot': '가수',
  'recorded_at': time,
  'song_id': 'song',
  'key_mode': 'MALE',
  'key_shift': 0,
  'version_code': 'NORMAL',
  'tier': null,
  'condition_code': 'GOOD',
  'tags': [
    {'id': 'tag1', 'name_snapshot': '연습'},
    {'id': 'tag2', 'name_snapshot': '보관 태그'},
  ],
  '_file_status': status(DeviceAudioState.available, 'NONE'),
};
RecordingFileStatus status(
  DeviceAudioState device,
  String cloud, {
  String? reason,
}) => RecordingFileStatus(
  recording: 'id',
  information: InformationSyncState.synced,
  device: device,
  serverState: cloud,
  blockedReason: reason,
  pinCurrent: false,
  pinPending: false,
);
void main() {
  test('AND fields distinguish shift zero, unset tier, unlinked, tag identity and interval boundaries', () {
    final filter = RecordingFilter({
      'start': '2026-12-31',
      'end': '2026-12-31',
      'song_id': 'song',
      'key_mode': 'MALE',
      'key_shift': '0',
      'version_code': 'NORMAL',
      'tier': 'UNSET',
      'condition_code': 'GOOD',
      'tag': 'tag2',
      'file': 'localOnly',
    });
    filter.validate();
    final r = record('id', '2026-12-30T15:00:00Z');
    expect(filter.matches(r), isTrue);
    expect(
      filter.matches({...r, 'recorded_at': '2026-12-30T14:59:59.999Z'}),
      isFalse,
    );
    expect(
      filter.matches({...r, 'recorded_at': '2026-12-31T15:00:00Z'}),
      isFalse,
    );
    for (final change in [
      {'song_id': null},
      {'key_mode': 'ORIGINAL'},
      {'key_shift': 1},
      {'version_code': 'MR'},
      {'tier': 'S'},
      {'condition_code': null},
      {'tags': <Map<String, dynamic>>[]},
    ]) {
      expect(filter.matches({...r, ...change}), isFalse);
    }
    expect(
      RecordingFilter({
        'song_id': 'UNLINKED',
        'tier': 'UNSET',
        'key_shift': '0',
      }).matches({...r, 'song_id': null}),
      isTrue,
    );
    expect(
      RecordingFilter({'condition_code': 'UNSET'})
          .matches({...r, 'condition_code': null}),
      isTrue,
    );
    expect(RecordingFilter().count, 0);
    expect(
      RecordingFilter({'start': '2026-12-31', 'end': '2026-12-31'}).count,
      1,
    );
  });
  test('date validation handles leap/month/year and inclusive start exclusive next day', () {
    expect(parseRecordingDate('2024-02-29'), DateTime.utc(2024, 2, 29));
    for (final invalid in [
      '2026-02-29',
      '2026-13-01',
      '2026-01-00',
      '2026-1-1',
    ]) {
      expect(() => parseRecordingDate(invalid), throwsFormatException);
    }
    expect(
      () =>
          RecordingFilter({'start': '2026-01-02', 'end': '2026-01-01'})
              .validate(),
      throwsFormatException,
    );
    final r = record('id', '2024-02-29T14:59:59.999Z');
    expect(RecordingFilter({'end': '2024-02-29'}).matches(r), isTrue);
    expect(
      RecordingFilter({'end': '2024-02-29'})
          .matches({...r, 'recorded_at': '2024-02-29T15:00:00Z'}),
      isFalse,
    );
  });
  test(
    'file filters distinguish unknown, quota and present/server combinations',
    () {
      expect(
        RecordingFileFilter.localOnly.matches(
          status(DeviceAudioState.available, 'UNKNOWN'),
        ),
        isFalse,
      );
      expect(
        RecordingFileFilter.neither.matches(
          status(DeviceAudioState.unknown, 'NONE'),
        ),
        isFalse,
      );
      expect(
        RecordingFileFilter.serverOnly.matches(
          status(DeviceAudioState.missing, 'STORED'),
        ),
        isTrue,
      );
      expect(
        RecordingFileFilter.both.matches(
          status(DeviceAudioState.available, 'STORED'),
        ),
        isTrue,
      );
      expect(
        RecordingFileFilter.localOnly.matches(
          status(DeviceAudioState.available, 'QUEUED', reason: 'QUOTA'),
        ),
        isTrue,
      );
      expect(
        RecordingFileFilter.quota.matches(
          status(DeviceAudioState.available, 'QUEUED', reason: 'QUOTA'),
        ),
        isTrue,
      );
      expect(
        RecordingFileFilter.neither.matches(
          status(DeviceAudioState.missing, 'NONE'),
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'draft cancel, apply, reset cancel and reset apply are distinct',
    (tester) async {
      final rows = [record('a', '2026-10-10T00:00:00Z')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingList(rows: rows, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.tap(find.text('필터 0'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('start')), '2026-10-11');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('저장 녹음 1개'), findsOneWidget);
      await tester.tap(find.text('필터 0'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('start')), '2026-10-11');
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(find.text('조건에 맞는 녹음이 없습니다'), findsOneWidget);
      expect(find.text('필터 1'), findsOneWidget);
      await tester.tap(find.text('필터 1'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1300));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('초기화'));
      await tester.tap(find.text('초기화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('필터 1'), findsOneWidget);
      await tester.tap(find.text('필터 1'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1300));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('초기화'));
      await tester.tap(find.text('초기화'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(find.text('필터 0'), findsOneWidget);
      expect(find.text('저장 녹음 1개'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown file state shows provisional count without false empty result',
    (tester) async {
      final r = record('a', '2026-10-10T00:00:00Z')
        ..['_file_status'] = status(DeviceAudioState.unknown, 'NONE');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingList(rows: [r], onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.tap(find.text('필터 0'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('file:null')));
      await tester.tap(find.byKey(const ValueKey('file:null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('현재 기기에 파일 없음').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(find.text('현재 확인된 0개'), findsOneWidget);
      expect(find.text('파일 상태 확인 불가 · 결과 개수를 아직 확정할 수 없어요.'), findsOneWidget);
      expect(find.text('조건에 맞는 녹음이 없습니다'), findsNothing);
    },
  );
  test('title sort uses normalized natural common key and latest tie', () {
    final rows = [
      {...record('b', '2026-10-10T00:00:00Z'), 'title_snapshot': 'Song 10'},
      {...record('c', '2026-10-09T00:00:00Z'), 'title_snapshot': 'Song 02'},
      {...record('a', '2026-10-10T00:00:00Z'), 'title_snapshot': 'song 2'},
    ];
    expect(sortRecordings(rows, RecordingSort.title).map((r) => r['id']), [
      'a',
      'c',
      'b',
    ]);
  });
}
