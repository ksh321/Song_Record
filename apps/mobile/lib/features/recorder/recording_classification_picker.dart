import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

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
    this.onApply,
    this.locked = false,
    this.applyLabel = '적용',
    super.key,
  });
  final Future<void> Function(RecordingClassification)? onApply;
  final bool locked;
  final String applyLabel;
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
  String? error;
  bool get editable => !busy && !widget.locked;
  Future<void> apply() async {
    if (busy || !widget.isCurrent()) return;
    final selection = (condition: condition, tags: selected.toList());
    final save = widget.onApply;
    if (save == null) {
      Navigator.pop<RecordingClassification>(context, selection);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await save(selection);
    } catch (_) {
      if (mounted) setState(() => error = '저장하지 못했어요. 선택은 유지돼요. 다시 저장해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manage() async {
    if (!editable || !widget.isCurrent() || widget.manage == null) return;
    setState(() => busy = true);
    try {
      final next = await widget.manage!();
      if (mounted && widget.isCurrent()) {
        setState(() {
          options = next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '분류 정보를 확인하지 못했어요. 선택은 유지돼요. 다시 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget heading(String label, String action) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      if (widget.manage != null)
        OutlinedButton.icon(
          onPressed: !editable ? null : manage,
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
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: appPageBar(context, title: const Text('컨디션과 태그')),
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
                      const DropdownMenuItem(
                        value: null,
                        child: Text('선택 안 함'),
                      ),
                      for (final item in options.conditions)
                        DropdownMenuItem(
                          value: item['code'] as String,
                          child: Text(item['name'] as String),
                        ),
                    ],
                    onChanged: !editable
                        ? null
                        : (v) => setState(() => condition = v),
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
                                !editable ||
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
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
                          onPressed: busy ? null : apply,
                          child: Text(busy ? '저장 중' : widget.applyLabel),
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
    ),
  );
}
