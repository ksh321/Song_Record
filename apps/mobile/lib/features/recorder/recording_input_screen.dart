import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/identifiers.dart';
import '../../core/domain/input_validation.dart';
import '../../core/domain/recording_defaults.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/musical_key_picker.dart';
import '../../core/widgets/version_picker.dart';
import 'recording_song_picker.dart';

/// A recoverable input draft, separate from SAVED metadata and the capture file.
class RecordingInputScreen extends StatefulWidget {
  const RecordingInputScreen({
    required this.recording,
    required this.repository,
    required this.isCurrent,
    this.discoveryBuilder,
    this.wakeSync,
    this.tagLoader,
    super.key,
  });
  final Map<String, dynamic> recording;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final RecordingDiscoveryBuilder? discoveryBuilder;
  final VoidCallback? wakeSync;
  final Future<List<Map<String, dynamic>>> Function()? tagLoader;
  @override
  State<RecordingInputScreen> createState() => _RecordingInputScreenState();
}

class _RecordingInputScreenState extends State<RecordingInputScreen> {
  final title = TextEditingController(),
      artist = TextEditingController(),
      note = TextEditingController();
  late RecordingDefaultState defaults;
  late DateTime time;
  String? condition, songId, error;
  List<String> tags = [];
  List<Map<String, dynamic>> availableTags = [];
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
    final saved = row['input_form'] as Map? ?? {};
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
  }

  Future<void> loadTags() async {
    try {
      final rows =
          await (widget.tagLoader?.call() ??
              widget.repository.selectableRecordingTags());
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
    if (busy || !current) return;
    try {
      await preserve();
      if (!mounted || !current) return;
      setState(() => allowExit = true);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = '입력 보존에 실패했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> chooseSong() async {
    if (busy || !current) return;
    try {
      await preserve();
      if (!mounted || !current) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RecordingSongPicker(
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

  Future<void> save() async {
    if (busy || !current) return;
    final t = validateInput(InputField.title, title.text),
        a = validateInput(InputField.artist, artist.text),
        n = validateInput(InputField.note, note.text);
    if (!t.isValid ||
        !a.isValid ||
        !n.isValid ||
        defaults.key.mode == KeyMode.original && defaults.key.shift != 0) {
      setState(() => error = '곡명·가수는 1~200자, 메모는 2000자 이내로 입력해 주세요. 원키는 0이에요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (prepared == null) await preserve();
      prepared ??=
          {
              ...input(),
              'title_snapshot': t.value,
              'artist_snapshot': a.value,
              'note': n.value,
            }
            ..remove('key_edited')
            ..remove('version_edited');
      operationIds ??= widget.repository.recordingSaveOperationIds();
      if (!current) throw StateError('Account changed');
      await widget.repository.saveRecordingInput(id, prepared!, operationIds!);
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
        appBar: AppBar(
          title: const Text('녹음 정보 입력'),
          leading: IconButton(
            onPressed: busy ? null : exit,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AbsorbPointer(
              absorbing:
                  busy ||
                  !widget.isCurrent(widget.repository) ||
                  prepared != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('필수 정보를 입력하면 녹음을 저장해요. 입력 중 나가도 녹음 파일은 남아요.'),
                  OutlinedButton(
                    onPressed: chooseSong,
                    child: Text(
                      songId == null ? '내 곡 선택 / 새 곡 찾기' : '연결할 곡 변경',
                    ),
                  ),
                  TextField(
                    key: const ValueKey('recording-title'),
                    controller: title,
                    decoration: const InputDecoration(labelText: '곡명'),
                    onChanged: (_) => changed(),
                  ),
                  TextField(
                    key: const ValueKey('recording-artist'),
                    controller: artist,
                    decoration: const InputDecoration(labelText: '가수'),
                    onChanged: (_) => changed(),
                  ),
                  TextButton(
                    onPressed: key,
                    child: Text('키: ${formatMusicalKey(defaults.key)}'),
                  ),
                  TextButton(
                    onPressed: version,
                    child: Text('버전: ${formatVersionCode(defaults.version)}'),
                  ),
                  TextButton(
                    onPressed: correctTime,
                    child: Text(
                      '녹음 시각: ${wall.toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', '')} (${widget.recording['timezone_id']})',
                    ),
                  ),
                  if (songId != null)
                    TextButton(
                      onPressed: applyDefaults,
                      child: const Text('선택 곡의 키·버전 기본값 적용'),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: condition,
                    decoration: const InputDecoration(labelText: '컨디션 (선택)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('미선택')),
                      DropdownMenuItem(
                        value: 'VERY_GOOD',
                        child: Text('아주 좋음'),
                      ),
                      DropdownMenuItem(value: 'GOOD', child: Text('좋음')),
                      DropdownMenuItem(value: 'NORMAL', child: Text('보통')),
                      DropdownMenuItem(value: 'BAD', child: Text('안 좋음')),
                    ],
                    onChanged: (v) {
                      setState(() => condition = v);
                      changed();
                    },
                  ),
                  const Text('태그 (선택)'),
                  if (availableTags.isEmpty) const Text('선택할 태그가 없어요.'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final tag in availableTags)
                        FilterChip(
                          label: Text(tag['name'] as String),
                          selected: tags.contains(tag['id']),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                tags.add(tag['id'] as String);
                              } else {
                                tags.remove(tag['id']);
                              }
                            });
                            changed();
                          },
                        ),
                    ],
                  ),
                  TextField(
                    key: const ValueKey('recording-note'),
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '메모 (선택)'),
                    onChanged: (_) => changed(),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) Text(error!),
                FilledButton(
                  onPressed: busy || !widget.isCurrent(widget.repository)
                      ? null
                      : save,
                  child: Text(busy ? '저장 중' : '녹음 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
