import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/trash/bulk_recording_delete.dart';

import 'restore_candidate_song_test.dart' as fixtures;

class Actions extends fixtures.FakeTrash {
  final calls = <String>[];
  String? fail;
  VoidCallback? after;
  @override
  Future<void> trashRecording(String id, bool confirmed) async {
    expect(confirmed, isTrue);
    calls.add(id);
    after?.call();
    if (id == fail) {
      fail = null;
      throw StateError('synthetic');
    }
  }
}

void main() {
  testWidgets(
    'explicit confirmation, partial retry, and account fence protect selection',
    (t) async {
      final actions = Actions();
      var current = true;
      Future<void> open() async {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showBulkRecordingDelete(
                  context,
                  recordings: {'a': '첫 녹음', 'b': '둘째 녹음'},
                  actions: actions,
                  isCurrent: () => current,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        );
        await t.tap(find.text('열기'));
        await t.pumpAndSettle();
      }

      await open();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '휴지통으로 이동'))
            .onPressed,
        isNull,
      );
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(actions.calls, isEmpty);
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      actions.fail = 'b';
      await t.tap(find.text('휴지통으로 이동'));
      await t.pumpAndSettle();
      expect(actions.calls, ['a', 'b']);
      await t.tap(find.text('남은 녹음 다시 삭제'));
      await t.pumpAndSettle();
      expect(actions.calls, ['a', 'b', 'b']);
      actions.calls.clear();
      await open();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      actions.after = () => current = false;
      await t.tap(find.text('휴지통으로 이동'));
      await t.pumpAndSettle();
      expect(actions.calls, ['a']);
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
