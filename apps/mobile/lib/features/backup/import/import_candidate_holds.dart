import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ui_controls.dart';
import 'import_candidates.dart';

/// onTjSearch must open the existing TJ search flow with a fresh provider proof.
/// It is a navigation request, never a number conversion or import mutation.
class ImportCandidateHolds extends StatelessWidget {
  const ImportCandidateHolds({
    required this.holds,
    required this.onTjSearch,
    super.key,
  });
  final List<ImportCandidateHold> holds;
  final void Function(ImportCandidateHold hold) onTjSearch;
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: AppLayout.bodyPadding,
    itemCount: holds.length,
    itemBuilder: (context, index) {
      final hold = holds[index];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hold.searchQuery.isEmpty ? '다시 선택할 곡' : hold.searchQuery),
              Text(hold.reason),
              OutlinedButton(
                onPressed: () => onTjSearch(hold),
                child: const Text('TJ에서 찾아 다시 선택'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
