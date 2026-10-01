import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/conflict_review.dart';
import 'package:song_record/features/sync/conflict_screen.dart';

import 'change_payload_validation_test.dart'
    show songChange, payloadId, recordingWire;

class Actions implements ConflictActions {
  int calls = 0;
  bool fail = false, loadFail = false;
  Completer<void>? pending;
  Map<String, ConflictChoice>? choices;
  ConflictReview? supplied;
  @override
  Future<ConflictReview> review(String opId) async {
    if (loadFail) throw StateError('private error');
    if (supplied != null) return supplied!;
    return ConflictReview(
      QueuedMutation(
        opId: opId,
        localOrder: 1,
        entity: LocalEntity.song,
        entityId: payloadId,
        operation: LocalOperation.patch,
        state: 'CONFLICT',
        baseRevision: 1,
        payload: '{"base_revision":1,"note":"내 메모"}',
        basePayload: jsonEncode(songChange(payloadId, 1)),
        serverResponse: jsonEncode({
          'status': 409,
          'code': 'REVISION_CONFLICT',
          'current': {...songChange(payloadId, 2), 'note': '서버 메모'},
        }),
        attemptCount: 1,
      ),
      '{}',
    );
  }

  @override
  Future<void> resolve(
    ConflictReview review,
    Map<String, ConflictChoice> choices,
  ) async {
    calls++;
    this.choices = choices;
    await pending?.future;
    if (fail) throw StateError('private error');
  }
}

void main() {
  ConflictReview tags({required bool names}) {
    const a = '11111111-1111-4111-8111-111111111111',
        b = '22222222-2222-4222-8222-222222222222';
    final base = {
      ...recordingWire('RecordingEdited'),
      'id': payloadId,
      'revision': 1,
      'tags': <Map<String, dynamic>>[],
      'tag_ids': <String>[],
    };
    return ConflictReview(
      QueuedMutation(
        opId: 'op',
        localOrder: 1,
        entity: LocalEntity.recording,
        entityId: payloadId,
        operation: LocalOperation.patch,
        state: 'CONFLICT',
        baseRevision: 1,
        payload: jsonEncode({
          'base_revision': 1,
          'tag_ids': [a],
        }),
        basePayload: jsonEncode(base),
        serverResponse: jsonEncode({
          'status': 409,
          'code': 'REVISION_CONFLICT',
          'current': {
            ...base,
            'revision': 2,
            'tag_ids': [b],
            'tags': [
              {'id': b, 'name_snapshot': '서버 태그'},
            ],
          },
        }),
        attemptCount: 1,
      ),
      '{}',
      tagNames: names ? {a: '내 태그'} : {},
    );
  }

  Future<void> open(WidgetTester tester, Actions actions) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ConflictScreen(actions: actions, opId: 'test-op'),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows both inputs without sending until explicit selection', (
    tester,
  ) async {
    final actions = Actions();
    await open(tester, actions);
    expect(find.text('메모: 내 메모'), findsOneWidget);
    expect(find.text('메모: 서버 메모'), findsOneWidget);
    expect(actions.calls, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(actions.calls, 0);
  });
  for (final local in [true, false]) {
    testWidgets(
      'explicit ${local ? 'local' : 'server'} choice saves only once',
      (tester) async {
        final actions = Actions()..pending = Completer<void>();
        await open(tester, actions);
        final button = find.text(local ? '이 기기 입력 사용' : '서버 값 사용');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.tap(button);
        await tester.pump();
        expect(actions.calls, 1);
        expect(actions.choices, {
          'note': local ? ConflictChoice.local : ConflictChoice.server,
        });
        actions.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.text('열기'), findsOneWidget);
      },
    );
  }
  testWidgets('stale save does not report success and requires fresh review', (
    tester,
  ) async {
    final actions = Actions()..fail = true;
    await open(tester, actions);
    await tester.ensureVisible(find.text('서버 값 사용'));
    await tester.tap(find.text('서버 값 사용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('정보가 바뀌었거나'), findsOneWidget);
    expect(find.text('서버 값 사용'), findsNothing);
    expect(find.textContaining('private error'), findsNothing);
    await tester.tap(find.text('다시 확인'));
    await tester.pumpAndSettle();
    expect(find.text('서버 값 사용'), findsOneWidget);
  });
  testWidgets(
    'unavailable review shows preserved-input message without choices',
    (tester) async {
      await open(tester, Actions()..loadFail = true);
      expect(find.textContaining('입력은 보존돼요'), findsOneWidget);
      expect(find.text('서버 값 사용'), findsNothing);
      expect(find.textContaining('private error'), findsNothing);
    },
  );
  testWidgets('tag choices display names instead of internal IDs', (
    tester,
  ) async {
    await open(tester, Actions()..supplied = tags(names: true));
    expect(find.text('태그: 내 태그'), findsOneWidget);
    expect(find.text('태그: 서버 태그'), findsOneWidget);
    expect(find.textContaining('11111111'), findsNothing);
  });
  testWidgets('unknown tag names cannot become ambiguous choices', (
    tester,
  ) async {
    await open(tester, Actions()..supplied = tags(names: false));
    expect(find.text('서버 값 사용'), findsNothing);
    expect(find.textContaining('입력은 보존돼요'), findsOneWidget);
  });
}
