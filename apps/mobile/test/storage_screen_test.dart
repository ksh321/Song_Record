import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/settings/storage_screen.dart';

const id = '11111111-1111-4111-8111-111111111111';
StorageView view({bool replacing = false}) => StorageView(
  {
    for (final key in StorageView.labels.keys) key: 0,
    'used_bytes': 197,
    'quota_bytes': 1000,
    'pinned_used': 1,
    'pinned_limit': 10,
    'pinned_pending': 1,
    'entitlement_revision': 3,
  },
  [
    {
      'slot_no': 1,
      'revision': 7,
      'current_recording_id': replacing ? id : null,
      'pending_recording_id': '22222222-2222-4222-8222-222222222222',
    },
  ],
  [],
);
void main() {
  testWidgets(
    'recording-specific pin keeps revision and requires confirmation',
    (t) async {
      final commands = <(String, String, Map<String, Object?>)>[];
      await t.pumpWidget(
        MaterialApp(
          home: StorageScreen(
            recordingId: id,
            load: () async => view(replacing: true),
            requireCurrent: () {},
            command: (method, path, body, op) async =>
                commands.add((method, path, body)),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('고정 해제'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(commands, isEmpty);
      await t.tap(find.text('고정 해제'));
      await t.pumpAndSettle();
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      expect(commands.single.$1, 'DELETE');
      expect(commands.single.$2, '/v1/pins/1');
      expect(commands.single.$3, {'base_revision': 7});
    },
  );

  test('missing usage never becomes sample zero', () {
    expect(() => StorageView({}, [], []), throwsFormatException);
  });
  testWidgets(
    'pending cancellation uses displayed revision and cancel changes nothing',
    (t) async {
      final commands = <Map<String, Object?>>[];
      await t.pumpWidget(
        MaterialApp(
          home: StorageScreen(
            load: () async => view(),
            requireCurrent: () {},
            command: (method, path, body, op) async {
              commands.add({
                'method': method,
                'path': path,
                'body': body,
                'op': op,
              });
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('고정한 녹음'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('고정 대기 취소'), 300);
      await t.tap(find.text('고정 대기 취소'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(commands, isEmpty);
      await t.tap(find.text('고정 대기 취소'));
      await t.pumpAndSettle();
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      expect(commands.single['method'], 'DELETE');
      expect(commands.single['path'], '/v1/pins/1');
      expect(commands.single['body'], {'base_revision': 7});
      await t.scrollUntilVisible(find.text('서버 사본 정리'), -250);
      await t.tap(find.text('서버 사본 정리'));
      await t.pumpAndSettle();
      expect(find.textContaining('공간 확보를 약속'), findsOneWidget);
    },
  );
  testWidgets(
    'uncertain reply retries exact same command; replacement cancellation preserves current',
    (t) async {
      final commands = <(String, String, Map<String, Object?>, String)>[];
      await t.pumpWidget(
        MaterialApp(
          home: StorageScreen(
            load: () async => view(replacing: true),
            requireCurrent: () {},
            command: (method, path, body, op) async {
              commands.add((method, path, body, op));
              if (commands.length == 1) throw TimeoutException('fixture');
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('고정한 녹음'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('교체 대기 취소'), 300);
      await t.tap(find.text('교체 대기 취소'));
      await t.pumpAndSettle();
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('같은 요청 결과 다시 확인'), -300);
      await t.tap(find.text('같은 요청 결과 다시 확인'));
      await t.pumpAndSettle();
      expect(commands, hasLength(2));
      expect(commands[1], commands[0]);
      expect(commands[0].$2, '/v1/pins/1/replacement/cancel');
      expect(commands[0].$3, {'base_revision': 7});
    },
  );
  testWidgets('old account cannot display a late response', (t) async {
    final response = Completer<StorageView>();
    final n = ChangeNotifier();
    var valid = true;
    await t.pumpWidget(
      MaterialApp(
        home: StorageScreen(
          load: () => response.future,
          requireCurrent: () {
            if (!valid) throw StateError('changed');
          },
          accountChanges: n,
          command: (_, _, _, _) async {},
        ),
      ),
    );
    valid = false;
    n.notifyListeners();
    response.complete(view());
    await t.pumpAndSettle();
    expect(find.text('197 B'), findsNothing);
    expect(find.textContaining('로그인 상태'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    n.dispose();
  });
}
