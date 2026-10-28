import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/trash/bulk_song_delete.dart';
import 'package:song_record/features/trash/trash_workflow.dart';

class _Trash implements TrashActions {
  final calls = <String>[];
  bool failSecond = false;
  @override
  Future<Map<String, dynamic>> preview(String id) async => {
    'preview_version': 'v-$id',
  };
  @override
  Future<void> trashSong(String id, String mode, String version) async {
    if (id == 'b' && failSecond) throw StateError('retry');
    calls.add('$id:$mode:$version');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('cancel preserves data and retry skips completed songs', (
    tester,
  ) async {
    final trash = _Trash();
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBulkSongDelete(
                context,
                ids: ['a', 'b'],
                actions: trash,
                isCurrent: () => current,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(trash.calls, isEmpty);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    trash.failSecond = true;
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(trash.calls, ['a:SONG_ONLY:v-a']);
    trash.failSecond = false;
    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(trash.calls, ['a:SONG_ONLY:v-a', 'b:SONG_ONLY:v-b']);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(trash.calls.length, 2);
  });
}
