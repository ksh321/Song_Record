import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';

import 'restore_candidate_song_test.dart' as trash;
import 'song_detail_test.dart' as fixture;

class _Trash extends trash.FakeTrash {
  int deletes = 0;
  @override
  Future<void> trashRecording(String id, bool confirmed) async {
    deletes++;
  }
}

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'linked recordings share stable multi-select and cancel without delete light=$light',
      (t) async {
        final data = StreamController<MySongDetail>.broadcast();
        final actions = _Trash();
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.preview(light: light),
            home: SongDetailScreen(watch: () => data.stream, trash: actions),
          ),
        );
        data.add(
          MySongDetail({
            'song': fixture.song(),
            'revision': 0,
            'recordings': [fixture.recording(30), fixture.recording(31)],
          }),
        );
        await t.pump();
        final row = find.byKey(ValueKey('linked-recording-${fixture.id(30)}'));
        await t.scrollUntilVisible(
          row,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        final top = t.getTopLeft(row).dy;
        await t.longPress(row);
        await t.pumpAndSettle();
        expect(find.text('전체 1'), findsOneWidget);
        expect(t.getTopLeft(row).dy, closeTo(top, 1));
        await t.tap(find.text('전체 1'));
        await t.pumpAndSettle();
        expect(find.text('전체 2'), findsOneWidget);
        await t.tap(find.text('선택한 2개 녹음 삭제'));
        await t.pumpAndSettle();
        expect(find.text('휴지통으로 이동'), findsOneWidget);
        expect(actions.deletes, 0);
        await t.tap(find.widgetWithText(TextButton, '취소'));
        await t.pumpAndSettle();
        expect(actions.deletes, 0);
        await t.tap(find.text('취소'));
        await t.pumpAndSettle();
        expect(find.text('전체 2'), findsNothing);
        await t.pumpWidget(const SizedBox());
        await t.runAsync(data.close);
        expect(t.takeException(), isNull);
      },
    );
  }
}
