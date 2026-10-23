import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/domain/condition_types.dart';
import '../../core/domain/identifiers.dart';
import '../../core/domain/input_validation.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';
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
  String page = 'personal';
  LocalHistoryEntry? pageHistory;
  final newName = TextEditingController();
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
          newName.clear();
          lastName = '';
          busy = false;
          message = '로그인 상태가 바뀌었어요. 설정을 다시 열어 주세요.';
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    newName.dispose();
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
    String? enteredName,
  }) async {
    final kind = condition ? '컨디션' : '태그';
    final route = condition ? 'conditions' : 'tags';
    final epoch = generation;
    String? value = enteredName;
    if (value == null) {
      dialogOpen = true;
      if (archive) {
        value = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('$kind 삭제'),
            content: Text('선택 목록에서 삭제해요. 기존 녹음에 표시된 $kind 이름은 그대로 남아요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'archive'),
                child: const Text('삭제'),
              ),
            ],
          ),
        );
      } else {
        value = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => _ClassificationNameScreen(
              kind: kind,
              initial: tag?['name'] as String? ?? lastName,
              condition: condition,
            ),
          ),
        );
      }
      dialogOpen = false;
    }
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

  void showPage(String next) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (next == 'personal') {
      final previous = pageHistory;
      pageHistory = null;
      previous?.remove();
    } else if (pageHistory == null) {
      pageHistory = LocalHistoryEntry(
        onRemove: () {
          pageHistory = null;
          if (mounted) {
            setState(() {
              page = 'personal';
              newName.clear();
              message = null;
            });
          }
        },
      );
      ModalRoute.of(context)?.addLocalHistoryEntry(pageHistory!);
    }
    setState(() {
      page = next;
      newName.clear();
      message = null;
    });
  }

  Future<void> add(bool condition) async {
    final value = validateInput(
      condition ? InputField.condition : InputField.tag,
      newName.text,
    );
    if (!value.isValid) {
      setState(() => message = '앞뒤 공백을 제외한 1~50자로 입력해 주세요.');
      return;
    }
    await edit(null, condition: condition, enteredName: value.value);
    if (mounted && pending == null && data != null) newName.clear();
  }

  Widget menuRow(String title, String subtitle, IconData icon, String next) =>
      AppFeatureRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: () => showPage(next),
      );

  String summary(List<Map<String, dynamic>>? entries) => entries == null
      ? '목록 확인 중'
      : entries
            .where((r) => r['archived_at'] == null)
            .map((r) => r['name'] as String)
            .join(' · ');

  List<Widget> personal() => [
    AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          menuRow('강조색', '7가지 색상에서 선택', Icons.palette_outlined, 'accent'),
          const Divider(height: 1),
          menuRow(
            '컨디션 관리',
            summary(data?.conditions),
            Icons.graphic_eq,
            'conditions',
          ),
          const Divider(height: 1),
          menuRow('태그 관리', summary(data?.tags), Icons.playlist_add, 'tags'),
        ],
      ),
    ),
  ];

  List<Widget> accents() => [
    ValueListenableBuilder<AppAccent>(
      valueListenable: widget.accent,
      builder: (context, value, _) => LayoutBuilder(
        builder: (context, bounds) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final a in AppAccent.values.where((a) => a != AppAccent.white))
              SizedBox(
                width: (bounds.maxWidth - 10) / 2,
                child: Semantics(
                  selected: value == a,
                  button: true,
                  child: OutlinedButton(
                    onPressed: colorBusy ? null : () => color(a),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      side: BorderSide(
                        color: value == a
                            ? a.background
                            : Theme.of(context).colorScheme.outline,
                        width: value == a ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: a.background,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            a.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 14),
    const AppPanel(
      child: Text('선택한 강조색을 버튼과 활성 탭에 적용합니다.', style: TextStyle(fontSize: 12)),
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: colorBusy ? null : () => showPage('personal'),
      child: const Text('완료'),
    ),
  ];

  List<Widget> management(bool condition) {
    final kind = condition ? '컨디션' : '태그';
    final entries = condition ? data?.conditions : data?.tags;
    final editable = !busy && pending == null && widget.canEdit && data != null;
    return [
      Text(
        '자주 쓰는 $kind${condition ? '을' : '를'} 준비해 두세요. 삭제해도 기존 녹음의 표시는 유지돼요.',
        style: TextStyle(
          fontSize: 12,
          height: 1.85,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 14),
      if (entries != null)
        for (final item in entries.where((r) => r['archived_at'] == null))
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item['name'] as String,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: condition ? '컨디션 이름 변경' : '이름 변경',
                  onPressed: editable
                      ? () => edit(item, condition: condition)
                      : null,
                  icon: const AppIcon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: '$kind 삭제',
                  onPressed: editable
                      ? () => edit(item, condition: condition, archive: true)
                      : null,
                  icon: const AppIcon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
          ),
      if (entries != null && !entries.any((r) => r['archived_at'] == null))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('등록한 $kind${condition ? '이' : '가'} 없어요.'),
        ),
      const SizedBox(height: 16),
      AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('새 $kind', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: newName,
                    enabled: editable,
                    decoration: InputDecoration(hintText: '이름 입력'),
                    onSubmitted: editable ? (_) => add(condition) : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: editable ? () => add(condition) : null,
                  child: const Text('추가'),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (page) {
      'accent' => '강조색',
      'conditions' => '컨디션 관리',
      'tags' => '태그 관리',
      _ => '개인화와 분류',
    };
    return Scaffold(
      appBar: appPageBar(
        context,
        title: Text(title),
        leading: page == 'personal'
            ? null
            : IconButton(
                tooltip: '이전 화면',
                onPressed: () => showPage('personal'),
                icon: const AppIcon(Icons.arrow_back),
              ),
        actions: const [ThemeToggle()],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppLayout.bodyPadding,
          children: [
            if (!widget.canEdit && page != 'accent')
              const Text('분류 변경은 동기화 연결이 필요해요.'),
            ...switch (page) {
              'accent' => accents(),
              'conditions' => management(true),
              'tags' => management(false),
              _ => personal(),
            },
            if (busy || colorBusy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(message!, style: const TextStyle(fontSize: 12)),
                ),
              ),
            if (pending != null)
              FilledButton(
                onPressed: busy ? null : submit,
                child: const Text('같은 요청 다시 확인'),
              ),
            if (page != 'accent' && (data == null && !busy || pending != null))
              TextButton(
                onPressed: busy || pending != null ? null : reload,
                child: const Text('새로고침'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationNameScreen extends StatefulWidget {
  const _ClassificationNameScreen({
    required this.kind,
    required this.initial,
    required this.condition,
  });
  final String kind, initial;
  final bool condition;
  @override
  State<_ClassificationNameScreen> createState() => _NameState();
}

class _NameState extends State<_ClassificationNameScreen> {
  late final controller = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save() {
    final value = validateInput(
      widget.condition ? InputField.condition : InputField.tag,
      controller.text,
    );
    if (!value.isValid) {
      setState(() => error = '앞뒤 공백을 제외한 1~50자로 입력해 주세요.');
      return;
    }
    Navigator.pop(context, value.value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(
      context,
      title: const Text('이름 변경'),
      actions: const [ThemeToggle()],
    ),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('이름', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: '이름 입력',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: save,
                        child: const Text('저장'),
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
