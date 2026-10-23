import 'package:flutter/material.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';

typedef ClassificationOptions = ({
  List<Map<String, dynamic>> conditions,
  List<Map<String, dynamic>> tags,
});
typedef RecordingClassification = ({String? condition, List<String> tags});

/// A cancellable UI draft. Only the returned selection is applied by the
/// existing recording input screen; definition management keeps its own flow.
class RecordingClassificationPicker extends StatefulWidget {
  const RecordingClassificationPicker({
    required this.options,
    required this.selection,
    required this.isCurrent,
    this.manage,
    super.key,
  });
  final ClassificationOptions options;
  final RecordingClassification selection;
  final bool Function() isCurrent;
  final Future<ClassificationOptions> Function()? manage;
  @override
  State<RecordingClassificationPicker> createState() => _State();
}

class _State extends State<RecordingClassificationPicker> {
  late String? condition = widget.selection.condition;
  late final selected = widget.selection.tags.toSet();
  late ClassificationOptions options = widget.options;
  bool busy = false;
  Future<void> manage() async {
    if (busy || !widget.isCurrent() || widget.manage == null) return;
    setState(() => busy = true);
    try {
      final next = await widget.manage!();
      if (mounted && widget.isCurrent()) setState(() => options = next);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget heading(String label, String action) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      if (widget.manage != null)
        OutlinedButton.icon(
          onPressed: busy ? null : manage,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            textStyle: const TextStyle(fontFamily: 'ReferenceKR', fontSize: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const AppIcon(Icons.edit_outlined, size: 14),
          label: Text(action),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('컨디션과 태그')),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading('컨디션', '컨디션 수정'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: condition,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('선택 안 함')),
                    for (final item in options.conditions)
                      DropdownMenuItem(
                        value: item['code'] as String,
                        child: Text(item['name'] as String),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => condition = v),
                ),
                const SizedBox(height: 16),
                heading('태그', '태그 수정'),
                const SizedBox(height: 6),
                AppPanel(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      if (options.tags.isEmpty) const Text('선택할 태그가 없어요.'),
                      for (final tag in options.tags)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            '${tag['name']}${tag['historical'] == true ? ' (기존 기록)' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: selected.contains(tag['id']),
                          onChanged:
                              busy ||
                                  tag['historical'] == true &&
                                      !selected.contains(tag['id'])
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    selected.add(tag['id'] as String);
                                  } else {
                                    selected.remove(tag['id']);
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () {
                                if (!widget.isCurrent()) return;
                                Navigator.pop<RecordingClassification>(
                                  context,
                                  (
                                    condition: condition,
                                    tags: selected.toList(),
                                  ),
                                );
                              },
                        child: const Text('적용'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
