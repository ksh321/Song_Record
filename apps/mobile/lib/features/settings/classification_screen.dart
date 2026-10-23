import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/domain/condition_types.dart';
import '../../core/domain/identifiers.dart';
import '../../core/domain/input_validation.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import 'settings_api.dart';

typedef ClassificationData = ({
  List<Map<String, dynamic>> tags,
  List<Map<String, dynamic>> conditions,
});

class ClassificationScreen extends StatefulWidget {
  const ClassificationScreen({
    required this.load,
    required this.command,
    required this.requireCurrent,
    required this.accent,
    required this.saveAccent,
    this.canEdit = true,
    this.accountChanges,
    super.key,
  });
  final Future<ClassificationData> Function() load;
  final Future<void> Function(String, String, Map<String, Object?>, String)
  command;
  final VoidCallback requireCurrent;
  final ValueListenable<AppAccent> accent;
  final Future<void> Function(AppAccent) saveAccent;
  final Listenable? accountChanges;
  final bool canEdit;
  @override
  State<ClassificationScreen> createState() => _ClassificationState();
}

class _ClassificationState extends State<ClassificationScreen> {
  ClassificationData? data;
  bool busy = false, colorBusy = false, dialogOpen = false;
  int generation = 0;
  String? message;
  String lastName = '';
  ({String method, String path, Map<String, Object?> body, String op})? pending;
  @override
  void initState() {
    super.initState();
    widget.accountChanges?.addListener(accountChanged);
    reload();
  }

  void accountChanged() {
    try {
      widget.requireCurrent();
    } catch (_) {
      generation++;
      if (mounted) {
        if (dialogOpen) {
          dialogOpen = false;
          Navigator.of(context).pop();
        }
        setState(() {
          data = null;
          pending = null;
          busy = false;
          message = '로그인 상태가 바뀌었어요. 설정을 다시 열어 주세요.';
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    widget.accountChanges?.removeListener(accountChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClassificationScreen old) {
    super.didUpdateWidget(old);
    if (old.accountChanges != widget.accountChanges) {
      old.accountChanges?.removeListener(accountChanged);
      widget.accountChanges?.addListener(accountChanged);
    }
    if (old.load != widget.load ||
        old.requireCurrent != widget.requireCurrent) {
      pending = null;
      reload();
    }
  }

  Future<void> reload() async {
    final epoch = ++generation;
    setState(() {
      busy = true;
      data = null;
    });
    try {
      widget.requireCurrent();
      final next = await widget.load();
      widget.requireCurrent();
      final identities = <String>{};
      for (final tag in next.tags) {
        UuidValue(tag['id'] as String);
        if (!identities.add(tag['id'] as String) ||
            tag['name'] is! String ||
            tag['revision'] is! int ||
            (tag['revision'] as int) < 1) {
          throw const FormatException('Invalid tag');
        }
      }
      final codes = <String>{};
      for (final item in next.conditions) {
        UuidValue(item['id'] as String);
        if (!codes.add(item['code'] as String) ||
            !validConditionCode(item['code']) ||
            item['name'] is! String ||
            item['revision'] is! int ||
            (item['revision'] as int) < 1) {
          throw const FormatException('Invalid owned condition');
        }
      }
      if (mounted && epoch == generation) {
        setState(() {
          data = next;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(() {
          busy = false;
          message = '분류 정보를 확인하지 못했어요. 새로고침해 주세요.';
        });
      }
    }
  }

  Future<void> submit() async {
    final p = pending;
    if (p == null || busy) return;
    final epoch = generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      widget.requireCurrent();
      await widget.command(p.method, p.path, p.body, p.op);
      widget.requireCurrent();
      if (!mounted || epoch != generation) return;
      setState(() {
        pending = null;
        busy = false;
        message = '분류 변경과 기기 반영을 확인했어요. 과거 녹음 이름은 유지됩니다.';
      });
      await reload();
    } catch (e) {
      if (!mounted || epoch != generation) return;
      final rejected =
          e is SettingsUnavailable &&
          e.status != null &&
          e.status! >= 400 &&
          e.status! < 500;
      setState(() {
        busy = false;
        data = null;
        if (rejected) pending = null;
        message = rejected
            ? '최신 분류와 중복 이름·버전을 확인해 주세요.'
            : '변경 결과 또는 기기 반영을 확인하지 못했어요. 같은 요청으로 다시 확인하세요.';
      });
    }
  }

  Future<void> edit(
    Map<String, dynamic>? tag, {
    bool archive = false,
    bool condition = false,
  }) async {
    final kind = condition ? '컨디션' : '태그';
    final route = condition ? 'conditions' : 'tags';
    final epoch = generation;
    final input = TextEditingController(
      text: tag?['name'] as String? ?? lastName,
    );
    String? error;
    dialogOpen = true;
    final value = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(
            archive
                ? '$kind 삭제'
                : tag == null
                ? '$kind 만들기'
                : '$kind 이름 변경',
          ),
          content: archive
              ? Text('선택 목록에서 삭제해요. 기존 녹음에 표시된 $kind 이름은 그대로 남아요.')
              : TextField(
                  controller: input,
                  decoration: InputDecoration(
                    labelText: '$kind 이름 (1~50자)',
                    errorText: error,
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (archive) {
                  Navigator.pop(c, 'archive');
                  return;
                }
                try {
                  final validated = validateInput(
                    condition ? InputField.condition : InputField.tag,
                    input.text,
                  );
                  if (!validated.isValid) {
                    setDialog(() => error = '앞뒤 공백을 제외한 1~50자로 입력해 주세요.');
                    return;
                  }
                  Navigator.pop(c, validated.value);
                } catch (_) {
                  setDialog(() => error = '올바른 문자를 입력해 주세요.');
                }
              },
              child: Text(archive ? '삭제' : '저장'),
            ),
          ],
        ),
      ),
    );
    dialogOpen = false;
    // Let the dialog's exit animation release its TextField before disposing.
    Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
    if (!mounted || epoch != generation || value == null) return;
    if (!archive) lastName = value;
    try {
      widget.requireCurrent();
    } catch (_) {
      accountChanged();
      return;
    }
    pending = (
      method: tag == null || archive ? 'POST' : 'PATCH',
      path: tag == null
          ? '/v1/$route'
          : '/v1/$route/${tag['id']}${archive ? '/archive' : ''}',
      body: {
        if (tag == null)
          'id': UuidValue.random().value
        else
          'base_revision': tag['revision'],
        if (!archive) 'name': value,
      },
      op: UuidValue.random().value,
    );
    await submit();
  }

  Future<void> color(AppAccent accent) async {
    setState(() => colorBusy = true);
    try {
      await widget.saveAccent(accent);
      if (mounted) {
        setState(() => message = '강조색을 이 기기에 저장했어요. 동기화·백업에는 포함하지 않습니다.');
      }
    } catch (_) {
      if (mounted) setState(() => message = '강조색을 저장하지 못했어요. 기존 색을 유지합니다.');
    } finally {
      if (mounted) setState(() => colorBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('개인화와 분류 관리')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('강조색 · 이 기기에만 저장'),
          if (!widget.canEdit) const Text('분류 변경은 동기화 연결이 필요해요.'),
          ValueListenableBuilder<AppAccent>(
            valueListenable: widget.accent,
            builder: (c, value, _) => Wrap(
              spacing: 8,
              children: [
                for (final a in AppAccent.values.where(
                  (a) => a != AppAccent.white,
                ))
                  ChoiceChip(
                    label: Text(a.label),
                    selected: value == a,
                    onSelected: colorBusy ? null : (_) => color(a),
                  ),
              ],
            ),
          ),
          if (busy || colorBusy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          if (pending != null)
            FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('같은 요청 다시 확인'),
            ),
          TextButton(
            onPressed: busy || pending != null ? null : reload,
            child: const Text('새로고침'),
          ),
          const Text('컨디션은 녹음마다 하나를 선택할 수 있어요.'),
          if (data case final current?) ...[
            FilledButton(
              onPressed: busy || pending != null || !widget.canEdit
                  ? null
                  : () => edit(null, condition: true),
              child: const Text('컨디션 만들기'),
            ),
            for (final r in current.conditions)
              if (r['archived_at'] == null)
                ListTile(
                  title: Text(r['name'] as String),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: '컨디션 이름 변경',
                        icon: const AppIcon(Icons.edit_outlined),
                        onPressed: busy || pending != null || !widget.canEdit
                            ? null
                            : () => edit(r, condition: true),
                      ),
                      IconButton(
                        tooltip: '컨디션 삭제',
                        icon: const AppIcon(Icons.delete_outline),
                        onPressed: busy || pending != null || !widget.canEdit
                            ? null
                            : () => edit(r, condition: true, archive: true),
                      ),
                    ],
                  ),
                ),
            FilledButton(
              onPressed: busy || pending != null || !widget.canEdit
                  ? null
                  : () => edit(null),
              child: const Text('태그 만들기'),
            ),
            const Text('태그는 여러 개 선택할 수 있어요. 수정·삭제해도 기존 녹음의 표시는 유지돼요.'),
            for (final tag in current.tags)
              if (tag['archived_at'] == null)
                ListTile(
                  title: Text(tag['name'] as String),
                  trailing: tag['archived_at'] != null
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              tooltip: '이름 변경',
                              onPressed:
                                  busy || pending != null || !widget.canEdit
                                  ? null
                                  : () => edit(tag),
                              icon: const AppIcon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '태그 삭제',
                              onPressed:
                                  busy || pending != null || !widget.canEdit
                                  ? null
                                  : () => edit(tag, archive: true),
                              icon: const AppIcon(Icons.delete_outline),
                            ),
                          ],
                        ),
                ),
            if (!current.tags.any((tag) => tag['archived_at'] == null))
              const Text('등록한 태그가 없어요.'),
          ],
        ],
      ),
    ),
  );
}
