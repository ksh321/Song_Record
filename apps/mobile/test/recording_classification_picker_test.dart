import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/recorder/recording_classification_picker.dart';

void main() {
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
