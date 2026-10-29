import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/recorder/recording_classification_picker.dart';

void main() {
  testWidgets(
    'direct save error keeps selection and allows same selection retry',
    (t) async {
      var attempts = 0, locked = false;
      final received = <RecordingClassification>[];
      await t.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => RecordingClassificationPicker(
              options: (
                conditions: [
                  {'code': 'GOOD', 'name': '좋음'},
                ],
                tags: [
                  {'id': 't', 'name': '발성'},
                ],
              ),
              selection: (condition: 'GOOD', tags: ['t']),
              isCurrent: () => true,
              locked: locked,
              applyLabel: '변경 저장',
              onApply: (value) async {
                received.add(value);
                attempts++;
                if (attempts == 1) {
                  update(() => locked = true);
                  throw StateError('synthetic');
                }
              },
            ),
          ),
        ),
      );
      await t.tap(find.text('변경 저장'));
      await t.pumpAndSettle();
      expect(find.textContaining('선택은 유지'), findsOneWidget);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNull,
      );
      await t.tap(find.text('변경 저장'));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(received[1].condition, received[0].condition);
      expect(received[1].tags, received[0].tags);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel discards selection; apply returns only the explicit draft',
    (t) async {
      RecordingClassification? result;
      var current = true;
      Future<void> open() async {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.push<RecordingClassification>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordingClassificationPicker(
                        options: (
                          conditions: [
                            {'code': 'GOOD', 'name': '좋음'},
                          ],
                          tags: [
                            {'id': 'active', 'name': '호흡'},
                            {'id': 'old', 'name': '과거 태그', 'historical': true},
                          ],
                        ),
                        selection: (condition: null, tags: ['old']),
                        isCurrent: () => current,
                      ),
                    ),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        );
        await t.tap(find.text('열기'));
        await t.pumpAndSettle();
      }

      await open();
      await t.tap(find.text('호흡'));
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(result, isNull);
      await open();
      await t.tap(find.text('호흡'));
      await t.tap(find.text('과거 태그 (기존 기록)'));
      await t.pump();
      final old = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, '과거 태그 (기존 기록)'),
      );
      expect(old.value, isFalse);
      expect(
        old.onChanged,
        isNull,
        reason: 'Archived tags cannot be newly selected.',
      );
      current = false;
      await t.tap(find.text('적용'));
      await t.pumpAndSettle();
      expect(find.text('컨디션과 태그'), findsOneWidget);
      expect(result, isNull);
      current = true;
      await t.tap(find.text('적용'));
      await t.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.condition, isNull);
      expect(result!.tags, ['active']);
    },
  );
}
