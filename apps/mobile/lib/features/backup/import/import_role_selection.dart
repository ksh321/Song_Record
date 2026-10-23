import 'package:flutter/material.dart';

import '../../../core/widgets/ui_controls.dart';
import 'import_roles.dart';

class ImportRoleSelection extends StatefulWidget {
  const ImportRoleSelection({
    required this.plan,
    required this.requireCurrent,
    required this.onSelected,
    super.key,
  });
  final ImportRolePlan plan;
  final void Function() requireCurrent;
  final void Function(Set<String>) onSelected;
  @override
  State<ImportRoleSelection> createState() => _ImportRoleSelectionState();
}

class _ImportRoleSelectionState extends State<ImportRoleSelection> {
  final selected = <String>{};
  @override
  void didUpdateWidget(covariant ImportRoleSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plan, widget.plan)) selected.clear();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.plan.pinCandidates.toList();
    final titles = {
      for (final r in widget.plan.records)
        if (r['entity'] == 'RECORDING')
          r['resource_id']: (r['payload'] as Map)['title_snapshot'],
    };
    return SafeArea(
      child: ListView.builder(
        padding: AppLayout.bodyPadding,
        itemCount: candidates.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              '기존 대표·고정 선택은 유지합니다.\n백업의 과거 고정은 선택한 항목만 재신청 후보로 준비합니다. 현재 여유 ${widget.plan.availablePinSlots}개 · 아직 신청하지 않았습니다.',
            );
          }
          if (index == candidates.length + 1) {
            return FilledButton(
              onPressed: () {
                final choices = widget.plan.selectPins(
                  selected,
                  widget.requireCurrent,
                );
                widget.onSelected(choices);
              },
              child: const Text('선택한 고정 재신청 후보 확인'),
            );
          }
          final id = candidates[index - 1];
          return CheckboxListTile(
            title: Text(titles[id] as String? ?? '복원 녹음'),
            value: selected.contains(id),
            onChanged:
                !selected.contains(id) &&
                    selected.length >= widget.plan.availablePinSlots
                ? null
                : (value) {
                    widget.requireCurrent();
                    setState(() {
                      if (value == true) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
                      }
                    });
                  },
          );
        },
      ),
    );
  }
}
