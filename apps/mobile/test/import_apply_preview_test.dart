import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/import/import_apply_preview.dart';
import 'package:song_record/features/backup/import/import_outcome.dart';

void main() {
  for (final conflicts in [0, 1]) {
    testWidgets('final import needs a tap and rejects conflicts=$conflicts', (
      tester,
    ) async {
      final changes = ChangeNotifier();
      addTearDown(changes.dispose);
      var applied = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ImportApplyPreview(
            information: 2,
            files: 1,
            held: 1,
            conflicts: conflicts,
            requireCurrent: () {},
            accountChanges: changes,
            apply: (guard) async {
              guard();
              applied++;
              return const ImportOutcome(
                information: 2,
                files: 1,
                missingFiles: 0,
                held: 1,
                conflicts: 0,
                pending: 0,
                uploadCandidates: {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(applied, 0);
      expect(find.text('이번에 가져오지 않는 항목 1개'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed == null, conflicts > 0);
      if (conflicts == 0) {
        await tester.ensureVisible(find.text('가져오기'));
        await tester.tap(find.text('가져오기'));
        await tester.pumpAndSettle();
        expect(applied, 1);
      }
    });
  }
}
