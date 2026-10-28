import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/domain/condition_types.dart';
import '../../core/domain/identifiers.dart';
import '../../core/domain/input_validation.dart';
import '../../core/domain/recording_defaults.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/musical_key_picker.dart';
import '../../core/widgets/song_discovery_sheet.dart';
import '../../core/widgets/tier_picker.dart';
import '../../core/widgets/ui_controls.dart';
import '../../core/widgets/version_picker.dart';
import 'recording_classification_picker.dart';
import 'recording_song_picker.dart';

/// A recoverable input draft, separate from SAVED metadata and the capture file.
class RecordingInputScreen extends StatefulWidget {
  const RecordingInputScreen({
    required this.recording,
    required this.repository,
    required this.isCurrent,
    this.discoveryBuilder,
    this.wakeSync,
    this.classificationBuilder,
    this.tagLoader,
    this.conditionLoader,
    this.editing = false,
    this.revision = 0,
    this.initialField,
    super.key,
  });
  final Map<String, dynamic> recording;
  final bool editing;
  final int revision;
  final String? initialField;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final RecordingDiscoveryBuilder? discoveryBuilder;
  final VoidCallback? wakeSync;
  final WidgetBuilder? classificationBuilder;
  final Future<List<Map<String, dynamic>>> Function()? tagLoader;
  final Future<List<Map<String, dynamic>>> Function()? conditionLoader;
  @override
  State<RecordingInputScreen> createState() => _RecordingInputScreenState();
}

class _RecordingInputScreenState extends State<RecordingInputScreen> {
  final title = TextEditingController(),
      artist = TextEditingController(),
      note = TextEditingController();
  late RecordingDefaultState defaults;
  late DateTime time;
  String? condition, songId, error, tier;
  List<String> tags = [];
  List<Map<String, dynamic>> availableTags = [];
  List<Map<String, dynamic>> availableConditions = [
    for (final e in defaultConditionNames.entries)
      {'code': e.key, 'name': e.value},
  ];

  Timer? timer;
  Future<void> writes = Future.value();
  bool busy = false, allowExit = false;
  List<String>? operationIds;
  Map<String, Object?>? prepared;
  bool get current => mounted && widget.isCurrent(widget.repository);
  String get id => widget.recording['id'] as String;

  @override
  void initState() {
    super.initState();
    final row = widget.recording;
    final saved = widget.editing ? row : row['input_form'] as Map? ?? {};
    final selection = row['input_selection'] as Map? ?? {};
    title.text =
        saved['title_snapshot'] as String? ??
        selection['title_snapshot'] as String? ??
        row['title_snapshot'] as String? ??
        '';
    artist.text =
        saved['artist_snapshot'] as String? ??
        selection['artist_snapshot'] as String? ??
        row['artist_snapshot'] as String? ??
        '';
    note.text = saved['note'] as String? ?? row['note'] as String? ?? '';
    songId = selection['song_id'] as String? ?? saved['song_id'] as String?;
    tier = widget.editing ? row['tier'] as String? : null;
    defaults = RecordingDefaultState(
      songId: songId == null ? null : SongId(songId!),
      key: MusicalKey(
        mode: KeyMode.values.firstWhere(
          (k) =>
              k.name.toUpperCase() ==
              (saved['key_mode'] ?? selection['key_mode'] ?? 'ORIGINAL'),
        ),
        shift:
            saved['key_shift'] as int? ?? selection['key_shift'] as int? ?? 0,
      ),
      version: VersionCode.values.firstWhere(
        (v) =>
            v.name.toUpperCase() ==
            (saved['version_code'] ?? selection['version_code'] ?? 'NORMAL'),
      ),
      keyEdited: saved['key_edited'] == true,
      versionEdited: saved['version_edited'] == true,
    );
    time = DateTime.parse(
      saved['recorded_at'] as String? ?? row['recorded_at'] as String,
    );
    condition = saved['condition_code'] as String?;
    tags = List<String>.from(saved['tag_ids'] as List? ?? []);
    unawaited(loadTags());
    unawaited(loadConditions());
    if (widget.editing && widget.initialField != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!current) return;
        if (widget.initialField == 'version') {
          await version();
        } else if (widget.initialField == 'key') {
          await key();
        } else if (widget.initialField == 'tier') {
          final result = await TierPicker.recording(
            context: context,
            selected: RecordingTier.values
                .where((value) => value.name.toUpperCase() == tier)
                .firstOrNull,
          );
          if (current && result != null) {
            setState(() => tier = result.value?.name.toUpperCase());
          }
        }
      });
    }
  }

  Future<void> loadConditions() async {
    try {
      final rows =
          await (widget.conditionLoader?.call() ??
              widget.repository.selectableRecordingConditions());
      if (!current) return;
      setState(() => availableConditions = rows);
    } catch (_) {
      if (current) setState(() => error = '컨디션 정보를 확인하지 못했어요. 입력은 유지돼요.');
    }
  }

  Future<void> loadTags() async {
    try {
      final rows =
          await (widget.tagLoader?.call() ??
              widget.repository.selectableRecordingTags());
      if (widget.editing) {
        for (final old
            in (widget.recording['tags'] as List? ?? [])
                .whereType<Map<String, dynamic>>()) {
          if (!rows.any((t) => t['id'] == old['id'])) {
            rows.add({
              'id': old['id'],
              'name': old['name_snapshot'],
              'historical': true,
            });
          }
        }
      }
      if (current) setState(() => availableTags = rows);
    } catch (_) {
      if (mounted) setState(() => error = '태그를 확인하지 못했어요. 녹음은 보존돼 있어요.');
    }
  }

  Map<String, Object?> input() => {
    'song_id': songId,
    'title_snapshot': title.text,
    'artist_snapshot': artist.text,
    'note': note.text,
    'key_mode': defaults.key.mode.name.toUpperCase(),
    'key_shift': defaults.key.shift,
    'version_code': defaults.version.name.toUpperCase(),
    'recorded_at': time.toUtc().toIso8601String(),
    'timezone_id': widget.recording['timezone_id'],
    'timezone_offset_minutes': widget.recording['timezone_offset_minutes'],
    'condition_code': condition,
    'tag_ids': [...tags],
    'key_edited': defaults.keyEdited,
    'version_edited': defaults.versionEdited,
  };
  Future<void> preserve() {
    timer?.cancel();
    final value = input();
    writes = writes.catchError((Object _) {}).then((_) async {
      if (!current) throw StateError('Account changed');
      await widget.repository.preserveRecordingInput(id, value);
    });
    return writes;
  }

  void changed() {
    if (widget.editing) return;
    timer?.cancel();
    timer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(
        preserve().catchError((Object _) {
          if (mounted) {
            setState(() => error = '입력을 보존하지 못했어요. 다시 저장해 주세요. 녹음 파일은 유지돼요.');
          }
        }),
      ),
    );
  }

  Future<void> exit() async {
    if (busy || allowExit || !current) return;
    // Repeated back gestures must not schedule two saves and pop two routes.
    setState(() => busy = true);
    try {
      if (!widget.editing) await preserve();
      if (!mounted || !current) return;
      setState(() => allowExit = true);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '입력 보존에 실패했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  Future<void> chooseSong() async {
    if (busy || !current) return;
    try {
      final source = await showRecordingSourceSheet(context);
      if (!mounted || !current || source == null) return;
      await preserve();
      if (!mounted || !current) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RecordingSongPicker(
            initialSource: source,
            closeOnSelected: true,
            recordingId: id,
            repository: widget.repository,
            isCurrent: widget.isCurrent,
            discoveryBuilder: widget.discoveryBuilder,
            wakeSync: widget.wakeSync,
          ),
        ),
      );
      if (!current) return;
      final rows = await widget.repository.pendingRecordings();
      if (!current) return;
      final row = rows.firstWhere((r) => r['id'] == id);
      final selected = row['input_selection'];
      if (selected is! Map) return;
      setState(() {
        songId = selected['song_id'] as String;
        title.text = selected['title_snapshot'] as String;
        artist.text = selected['artist_snapshot'] as String;
        defaults = defaults.selectSong(
          SongRecordingDefaults(
            songId: SongId(songId!),
            version: VersionCode.values.firstWhere(
              (v) => v.name.toUpperCase() == selected['version_code'],
            ),
            representativeKey: MusicalKey(
              mode: KeyMode.values.firstWhere(
                (k) => k.name.toUpperCase() == selected['key_mode'],
              ),
              shift: selected['key_shift'] as int,
            ),
          ),
        );
      });
      await preserve();
    } catch (_) {
      if (mounted) setState(() => error = '곡을 선택하지 못했어요. 입력과 파일은 유지돼요.');
    }
  }

  Future<void> manageClassifications() async {
    final builder = widget.classificationBuilder;
    if (builder == null || !current || busy) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
    if (!current) return;
    await loadConditions();
    await loadTags();
  }

  List<Map<String, dynamic>> classificationConditions() => [
    ...availableConditions,
    if (condition != null &&
        !availableConditions.any((r) => r['code'] == condition))
      {
        'code': condition,
        'name': widget.recording['condition_name_snapshot'] ?? '기존 컨디션',
      },
  ];
  Future<void> chooseClassifications() async {
    if (busy || !current) return;
    final result = await Navigator.of(context).push<RecordingClassification>(
      MaterialPageRoute(
        builder: (_) => RecordingClassificationPicker(
          options: (
            conditions: classificationConditions(),
            tags: availableTags,
          ),
          selection: (condition: condition, tags: List.of(tags)),
          isCurrent: () => current,
          manage: widget.classificationBuilder == null
              ? null
              : () async {
                  await manageClassifications();
                  return (
                    conditions: classificationConditions(),
                    tags: availableTags,
                  );
                },
        ),
      ),
    );
    if (result == null || !current) return;
    setState(() {
      condition = result.condition;
      tags = List.of(result.tags);
    });
    changed();
  }

  Future<void> applyDefaults() async {
    try {
      final rows = await widget.repository.pendingRecordings();
      if (!current) return;
      final selection = rows.firstWhere(
        (r) => r['id'] == id,
      )['input_selection'];
      if (selection is! Map) return;
      setState(
        () => defaults = defaults.applySongDefaults(
          SongRecordingDefaults(
            songId: SongId(selection['song_id'] as String),
            version: VersionCode.values.firstWhere(
              (v) => v.name.toUpperCase() == selection['version_code'],
            ),
            representativeKey: MusicalKey(
              mode: KeyMode.values.firstWhere(
                (k) => k.name.toUpperCase() == selection['key_mode'],
              ),
              shift: selection['key_shift'] as int,
            ),
          ),
        ),
      );
      changed();
    } catch (_) {
      if (mounted) setState(() => error = '기본값을 확인하지 못했어요. 직접 입력한 값은 유지돼요.');
    }
  }

  Future<void> key() async {
    final result = await MusicalKeyPicker.recording(
      context: context,
      selected: defaults.key,
    );
    if (!current || result == null) return;
    setState(() => defaults = defaults.editKey(result.value));
    changed();
  }

  Future<void> version() async {
    final result = await VersionPicker.show(
      context: context,
      selected: defaults.version,
    );
    if (!current || result == null) return;
    setState(() => defaults = defaults.editVersion(result.value));
    changed();
  }

  Future<void> editNote() async {
    if (!current || busy) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _RecordingNoteEditor(initial: note.text),
      ),
    );
    if (!current || result == null) return;
    setState(() => note.text = result);
    changed();
  }

  Future<void> correctTime() async {
    final offset = Duration(
      minutes: widget.recording['timezone_offset_minutes'] as int,
    );
    final wall = time.toUtc().add(offset);
    final date = await showDatePicker(
      context: context,
      initialDate: wall,
      firstDate: DateTime(1000),
      lastDate: DateTime(9999, 12, 31),
    );
    if (!mounted || !current || date == null) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(wall),
    );
    if (!current || clock == null) return;
    setState(
      () => time = DateTime.utc(
        date.year,
        date.month,
        date.day,
        clock.hour,
        clock.minute,
      ).subtract(offset),
    );
    changed();
  }

  List<String> get inputProblems => [
    if (!validateInput(InputField.title, title.text).isValid)
      title.text.trim().isEmpty ? '곡명' : '곡명 (200자 이내)',
    if (!validateInput(InputField.artist, artist.text).isValid)
      artist.text.trim().isEmpty ? '가수' : '가수 (200자 이내)',
    if (!validateInput(InputField.note, note.text).isValid) '메모 (2000자 이내)',
  ];

  Future<void> save() async {
    if (busy || !current) return;
    final t = validateInput(InputField.title, title.text),
        a = validateInput(InputField.artist, artist.text),
        n = validateInput(InputField.note, note.text);
    if (!t.isValid || !a.isValid || !n.isValid) {
      setState(() => error = '곡명·가수는 1~200자, 메모는 2000자 이내로 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (prepared == null && !widget.editing) await preserve();
      prepared ??=
          {
              ...input(),
              'title_snapshot': t.value,
              'artist_snapshot': a.value,
              'note': n.value,
            }
            ..remove('key_edited')
            ..remove('version_edited');
      if (widget.editing) {
        prepared!
          ..remove('song_id')
          ..['tier'] = tier;
      }
      operationIds ??= widget.editing
          ? widget.repository.recordingEditOperationIds()
          : widget.repository.recordingSaveOperationIds();
      if (!current) throw StateError('Account changed');
      if (widget.editing) {
        await widget.repository.saveRecordingDetails(
          id,
          prepared!,
          operationIds!,
          widget.recording,
          widget.revision,
        );
      } else {
        await widget.repository.saveRecordingInput(
          id,
          prepared!,
          operationIds!,
        );
      }
      if (!mounted || !current) return;
      widget.wakeSync?.call();
      setState(() => allowExit = true);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = '저장하지 못했어요. 입력·녹음 파일은 보존돼 있어요. 다시 저장해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _actions(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (inputProblems.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Text(
            '아직 입력하지 않았어요: ${!widget.editing && title.text.trim().isEmpty && artist.text.trim().isEmpty ? '곡 선택' : inputProblems.join(' · ')}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (error != null) Text(error!),
      if (widget.editing)
        TextButton(onPressed: busy ? null : exit, child: const Text('취소')),
      FilledButton(
        onPressed:
            busy ||
                !widget.isCurrent(widget.repository) ||
                inputProblems.isNotEmpty
            ? null
            : save,
        child: Text(
          busy
              ? '저장 중'
              : widget.editing
              ? '변경 저장'
              : '저장',
        ),
      ),
      if (!widget.editing) const SizedBox(height: 14),
      if (!widget.editing)
        OutlinedButton(
          onPressed: busy ? null : exit,
          child: const Text('나중에 입력'),
        ),
    ],
  );

  @override
  void dispose() {
    timer?.cancel();
    title.dispose();
    artist.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wall = time.toUtc().add(
      Duration(minutes: widget.recording['timezone_offset_minutes'] as int),
    );
    return PopScope(
      canPop: allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(exit());
      },
      child: Scaffold(
        appBar: appPageBar(
          context,
          title: Text(widget.editing ? '녹음 정보 수정' : '녹음 정보 입력'),
          leading: IconButton(
            onPressed: busy ? null : exit,
            icon: const AppIcon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: AppLayout.bodyPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AbsorbPointer(
                  absorbing:
                      busy ||
                      !widget.isCurrent(widget.repository) ||
                      prepared != null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.editing)
                        AppPickerField(
                          label: '곡 선택',
                          trailingLabel: title.text.trim().isEmpty
                              ? '선택 필요'
                              : null,
                          value: title.text.trim().isEmpty
                              ? '미선택'
                              : '${title.text} · ${artist.text}',
                          onPressed: chooseSong,
                        ),
                      if (widget.editing) ...[
                        AppLabeledField(
                          fieldKey: const ValueKey('recording-title'),
                          label: '곡명',
                          controller: title,
                          onChanged: (_) => setState(changed),
                        ),
                        const SizedBox(height: 14),
                        AppLabeledField(
                          fieldKey: const ValueKey('recording-artist'),
                          label: '가수',
                          controller: artist,
                          onChanged: (_) => setState(changed),
                        ),
                        const SizedBox(height: 14),
                      ],
                      AppPickerField(
                        label: '키',
                        value: formatMusicalKey(defaults.key),
                        onPressed: key,
                      ),
                      AppPickerField(
                        label: '버전',
                        value: formatVersionCode(defaults.version),
                        onPressed: version,
                      ),
                      if (widget.editing)
                        AppPickerField(
                          label: '녹음 시각',
                          onPressed: correctTime,
                          value:
                              '${wall.year}년 ${wall.month}월 ${wall.day}일 ${wall.hour < 12 ? '오전' : '오후'} ${wall.hour % 12 == 0 ? 12 : wall.hour % 12}:${wall.minute.toString().padLeft(2, '0')}',
                        ),
                      if (!widget.editing && songId != null)
                        TextButton(
                          onPressed: applyDefaults,
                          child: const Text('선택 곡의 키·버전 기본값 적용'),
                        ),
                      AppPickerField(
                        label: '컨디션·태그',
                        value: [
                          classificationConditions()
                                  .where((r) => r['code'] == condition)
                                  .firstOrNull?['name'] ??
                              '선택 안 함',
                          ...availableTags
                              .where((r) => tags.contains(r['id']))
                              .map((r) => r['name']),
                        ].join(' · '),
                        onPressed: chooseClassifications,
                      ),
                      if (widget.editing)
                        DropdownButtonFormField<String>(
                          key: const ValueKey('recording-tier'),
                          initialValue: tier,
                          decoration: const InputDecoration(labelText: '녹음 티어'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('미정'),
                            ),
                            for (final value in ['S', 'A', 'B', 'C', 'D'])
                              DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                          ],
                          onChanged: (v) => setState(() => tier = v),
                        ),
                      if (widget.editing)
                        AppLabeledField(
                          fieldKey: const ValueKey('recording-note'),
                          label: '메모 (선택)',
                          controller: note,
                          maxLines: 3,
                          onChanged: (_) => setState(changed),
                        )
                      else
                        AppPickerField(
                          label: '연습 메모',
                          value: note.text.isEmpty
                              ? '아직 입력하지 않았어요.'
                              : note.text,
                          onPressed: editNote,
                        ),
                    ],
                  ),
                ),
                if (!widget.editing) _actions(context),
              ],
            ),
          ),
        ),
        bottomNavigationBar: widget.editing
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _actions(context),
                ),
              )
            : null,
      ),
    );
  }
}

class _RecordingNoteEditor extends StatefulWidget {
  const _RecordingNoteEditor({required this.initial});
  final String initial;
  @override
  State<_RecordingNoteEditor> createState() => _RecordingNoteEditorState();
}

class _RecordingNoteEditorState extends State<_RecordingNoteEditor> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('연습 메모')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: AppLayout.bodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppLabeledField(
              fieldKey: const ValueKey('recording-note'),
              label: '연습 메모',
              controller: controller,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            const Text('최대 2,000자'),
            const SizedBox(height: 20),
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
                    onPressed:
                        validateInput(InputField.note, controller.text).isValid
                        ? () => Navigator.pop(context, controller.text)
                        : null,
                    child: const Text('적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
