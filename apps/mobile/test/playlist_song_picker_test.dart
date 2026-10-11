import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_song_picker.dart';
import 'package:song_record/features/songs/my_song.dart';

MySong song(int n, String title, {String? number}) => MySong({
  'id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  'title': title,
  'artist': 'Singer',
  'version_code': 'NORMAL',
  'lifecycle_state': 'ACTIVE',
  'tj_number': number,
});

void main() {
  testWidgets(
    'all songs shown; destination membership disables; search preserves selection; cancel saves nothing',
    (tester) async {
      final songs = [
        song(1, '이미 포함', number: '00123'),
        song(2, '선택 둘'),
        song(3, '선택 셋'),
      ];
      List<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<List<String>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SizedBox(
                      height: 500,
                      child: PlaylistSongPicker(
                        songs: songs,
                        items: [
                          {'entry_key': 'tj:00123'},
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('이미 포함'), findsOneWidget);
      expect(find.text('추가됨'), findsOneWidget);
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes.first.onChanged, isNull);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '셋');
      await tester.pump();
      expect(find.text('선택 둘'), findsNothing);
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      expect(find.text('2곡 추가'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('0곡 추가'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      await tester.tap(find.text('2곡 추가'));
      await tester.pumpAndSettle();
      expect(result, [songs[1].view.id.value, songs[2].view.id.value]);
      expect(playlistContainsSong([], songs.first), isFalse); // another list
    },
  );
}
