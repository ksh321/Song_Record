import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/domain/identifiers.dart';
import '../../core/domain/input_validation.dart';
import '../../core/theme/app_tokens.dart';
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
      if (next.conditions.length != 4 ||
          next.conditions.any((r) => r['name'] is! String) ||
          next.conditions.map((r) => r['code']).toSet().length != 4 ||
          !next.conditions.map((r) => r['code']).toSet().containsAll({
            'VERY_GOOD',
            'GOOD',
            'NORMAL',
            'BAD',
          })) {
        throw const FormatException('Invalid condition catalog');
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
        message = '태그 변경과 기기 반영을 확인했어요. 과거 녹음 이름은 유지됩니다.';
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
            ? '최신 태그와 중복 이름·버전을 확인해 주세요.'
            : '변경 결과 또는 기기 반영을 확인하지 못했어요. 같은 요청으로 다시 확인하세요.';
      });
    }
  }

  Future<void> edit(Map<String, dynamic>? tag, {bool archive = false}) async {
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
                ? '태그 보관'
                : tag == null
                ? '태그 만들기'
                : '태그 이름 변경',
          ),
          content: archive
              ? const Text('신규 선택에서 숨깁니다. 과거 녹음의 관계와 당시 이름은 유지됩니다.')
              : TextField(
                  controller: input,
                  decoration: InputDecoration(
                    labelText: '태그 이름 (1~50자)',
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
                  final validated = validateInput(InputField.tag, input.text);
                  if (!validated.isValid) {
                    setDialog(() => error = '앞뒤 공백을 제외한 1~50자로 입력해 주세요.');
                    return;
                  }
                  Navigator.pop(c, validated.value);
                } catch (_) {
                  setDialog(() => error = '올바른 문자를 입력해 주세요.');
                }
              },
              child: Text(archive ? '보관' : '저장'),
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
          ? '/v1/tags'
          : '/v1/tags/${tag['id']}${archive ? '/archive' : ''}',
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
          if (!widget.canEdit) const Text('태그 변경은 동기화 연결이 필요해요.'),
          ValueListenableBuilder<AppAccent>(
            valueListenable: widget.accent,
            builder: (c, value, _) => Wrap(
              spacing: 8,
              children: [
                for (final a in AppAccent.values)
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
          const Text(
            '컨디션은 고정 4단계이며 녹음마다 미선택 또는 하나를 선택합니다. 사용자 편집·보관은 태그에서 합니다.',
          ),
          if (data case final current?) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final r in current.conditions)
                  Chip(label: Text(r['name'] as String)),
              ],
            ),
            FilledButton(
              onPressed: busy || pending != null || !widget.canEdit
                  ? null
                  : () => edit(null),
              child: const Text('태그 만들기'),
            ),
            const Text('태그는 녹음에 여러 개 선택할 수 있어요. 이름 변경·보관은 과거 녹음 이름을 바꾸지 않습니다.'),
            for (final tag in current.tags)
              ListTile(
                title: Text(tag['name'] as String),
                subtitle: tag['archived_at'] == null
                    ? null
                    : const Text('보관됨 · 신규 선택에서 숨김'),
                trailing: tag['archived_at'] != null
                    ? null
                    : Wrap(
                        children: [
                          TextButton(
                            onPressed:
                                busy || pending != null || !widget.canEdit
                                ? null
                                : () => edit(tag),
                            child: const Text('이름 변경'),
                          ),
                          TextButton(
                            onPressed:
                                busy || pending != null || !widget.canEdit
                                ? null
                                : () => edit(tag, archive: true),
                            child: const Text('보관'),
                          ),
                        ],
                      ),
              ),
            if (current.tags.isEmpty) const Text('등록한 태그가 없어요.'),
          ],
        ],
      ),
    ),
  );
}
