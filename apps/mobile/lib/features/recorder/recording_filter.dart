import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/files/recording_file_status.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';

enum RecordingFileFilter {
  localOnly('이 기기에만 있음'),
  serverOnly('서버에 보관됨'),
  both('이 기기와 서버에 있음'),
  neither('현재 기기에 파일 없음'),
  quota('서버 보관 대기 · 용량 부족');

  const RecordingFileFilter(this.label);
  final String label;
  bool matches(RecordingFileStatus? status) {
    if (status == null) return false;
    if (this == quota) return status.blockedReason == 'QUOTA';
    if (status.device == DeviceAudioState.unknown ||
        status.serverState == 'UNKNOWN') {
      return false;
    }
    final local = status.device == DeviceAudioState.available,
        server = status.serverStored;
    return switch (this) {
      localOnly => local && !server,
      serverOnly => !local && server,
      both => local && server,
      neither => !local && !server,
      quota => false,
    };
  }
}

DateTime parseRecordingDate(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw const FormatException('YYYY-MM-DD 형식으로 입력해 주세요.');
  }
  final year = int.parse(text.substring(0, 4)),
      month = int.parse(text.substring(5, 7)),
      day = int.parse(text.substring(8));
  final date = DateTime.utc(year, month, day);
  if (year < 1000 ||
      date.year != year ||
      date.month != month ||
      date.day != day) {
    throw const FormatException('유효한 날짜를 입력해 주세요.');
  }
  return date;
}

class RecordingFilter {
  RecordingFilter([Map<String, String> values = const {}])
    : values = Map.unmodifiable(values);
  final Map<String, String> values;
  void validate() {
    final start = values['start'] == null
        ? null
        : parseRecordingDate(values['start']!);
    final end = values['end'] == null
        ? null
        : parseRecordingDate(values['end']!);
    if (start != null && end != null && start.isAfter(end)) {
      throw const FormatException('시작일은 종료일보다 늦을 수 없어요.');
    }
  }

  int get count =>
      values.length -
      (values.containsKey('start') && values.containsKey('end') ? 1 : 0);
  bool matches(Map<String, dynamic> row) {
    final time = DateTime.parse(row['recorded_at'] as String).toUtc();
    if (values['start'] case final String text) {
      if (time.isBefore(
        parseRecordingDate(text).subtract(const Duration(hours: 9)),
      )) {
        return false;
      }
    }
    if (values['end'] case final String text) {
      if (!time.isBefore(
        parseRecordingDate(text)
            .add(const Duration(days: 1))
            .subtract(const Duration(hours: 9)),
      )) {
        return false;
      }
    }
    for (final field in ['key_mode', 'version_code', 'condition_code']) {
      if (values[field] != null &&
          (values[field] == 'UNSET'
              ? row[field] != null
              : row[field] != values[field])) {
        return false;
      }
    }
    if (values['key_shift'] != null &&
        row['key_shift'].toString() != values['key_shift']) {
      return false;
    }
    if (values['song_id'] != null &&
        (values['song_id'] == 'UNLINKED'
            ? row['song_id'] != null
            : row['song_id'] != values['song_id'])) {
      return false;
    }
    if (values['tier'] != null &&
        (values['tier'] == 'UNSET'
            ? row['tier'] != null
            : row['tier'] != values['tier'])) {
      return false;
    }
    if (values['tag'] case final String id) {
      if (!(row['tags'] as List? ?? []).whereType<Map<String, dynamic>>().any(
        (t) => t['id'] == id,
      )) {
        return false;
      }
    }
    if (values['file'] case final String value) {
      if (!RecordingFileFilter.values
          .firstWhere((v) => v.name == value)
          .matches(row['_file_status'] as RecordingFileStatus?)) {
        return false;
      }
    }
    return true;
  }
}

class RecordingFilterScreen extends StatefulWidget {
  const RecordingFilterScreen({
    required this.initial,
    required this.rows,
    super.key,
  });
  final RecordingFilter initial;
  final List<Map<String, dynamic>> rows;
  @override
  State<RecordingFilterScreen> createState() => _RecordingFilterScreenState();
}

class _RecordingFilterScreenState extends State<RecordingFilterScreen> {
  late final draft = Map<String, String>.of(widget.initial.values);
  late final start = TextEditingController(text: draft['start']);
  late final end = TextEditingController(text: draft['end']);
  String? error;
  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  Widget choice(String field, String title, Map<String, String> options) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('$field:${draft[field]}'),
              initialValue: draft[field],
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                const DropdownMenuItem(value: null, child: Text('전체')),
                for (final entry in options.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(
                () =>
                    value == null ? draft.remove(field) : draft[field] = value,
              ),
            ),
          ],
        ),
      );
  Widget dateField(
    String field,
    String label,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: ValueKey(field),
        controller: controller,
        decoration: InputDecoration(
          hintText: '년-월-일',
          suffixIcon: IconButton(
            tooltip: '$label 선택',
            icon: const AppIcon(Icons.calendar_month_outlined),
            onPressed: () async {
              final current = DateTime.tryParse(controller.text);
              final selected = await showDatePicker(
                context: context,
                builder: (context, child) => Localizations.override(
                  context: context,
                  locale: const Locale('ko'),
                  delegates: GlobalMaterialLocalizations.delegates,
                  child: child!,
                ),
                initialDate:
                    current != null &&
                        current.year >= 1000 &&
                        current.year <= 9999
                    ? current
                    : DateTime.now(),
                firstDate: DateTime(1000),
                lastDate: DateTime(9999, 12, 31),
              );
              if (!mounted || selected == null) return;
              controller.text =
                  "${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}";
            },
          ),
        ),
      ),
      const SizedBox(height: 14),
    ],
  );
  void apply() {
    for (final entry in {
      'start': start.text.trim(),
      'end': end.text.trim(),
    }.entries) {
      if (entry.value.isEmpty) {
        draft.remove(entry.key);
      } else {
        draft[entry.key] = entry.value;
      }
    }
    final filter = RecordingFilter(draft);
    try {
      filter.validate();
      Navigator.pop(context, filter);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = <String, String>{
      for (final row in widget.rows)
        if (row['song_id'] is String)
          row['song_id'] as String: row['title_snapshot'] as String,
    };
    final tags = <String, String>{
      for (final row in widget.rows)
        for (final tag
            in (row['tags'] as List? ?? []).whereType<Map<String, dynamic>>())
          tag['id'] as String: tag['name_snapshot'] as String,
    };
    // Applied historical selections remain cancellable if the current list changes.
    for (final pair in [('song_id', songs), ('tag', tags)]) {
      final selected = draft[pair.$1];
      if (selected != null && selected != 'UNLINKED') {
        pair.$2.putIfAbsent(selected, () => '기존 선택');
      }
    }
    return Scaffold(
      appBar: appPageBar(context, title: const Text('녹음 필터')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppLayout.bodyPadding,
                children: [
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        dateField('start', '시작 날짜', start),
                        dateField('end', '종료 날짜', end),
                        choice('song_id', '곡', {'UNLINKED': '미연결', ...songs}),
                        choice('key_mode', '키 모드', {
                          'ORIGINAL': '원키',
                          'MALE': '남',
                          'FEMALE': '여',
                        }),
                        choice('key_shift', '반음', {
                          for (var i = -12; i <= 12; i++)
                            '$i': i > 0 ? '+$i' : '$i',
                        }),
                        choice('version_code', '버전', {
                          'NORMAL': '일반 반주',
                          'MR': 'MR',
                          'LIVE': 'LIVE',
                        }),
                        choice('tier', '티어', {
                          'S': 'S',
                          'A': 'A',
                          'B': 'B',
                          'C': 'C',
                          'D': 'D',
                          'UNSET': '미정',
                        }),
                        choice('condition_code', '컨디션', {
                          'VERY_GOOD': '매우 좋음',
                          'GOOD': '좋음',
                          'NORMAL': '보통',
                          'BAD': '안 좋음',
                          for (final row in widget.rows)
                            if (row['condition_code'] is String &&
                                row['condition_name_snapshot'] is String)
                              row['condition_code'] as String:
                                  row['condition_name_snapshot'] as String,
                          'UNSET': '미선택',
                        }),
                        choice('tag', '태그', tags),
                        choice('file', '파일 상태', {
                          for (final v in RecordingFileFilter.values)
                            v.name: v.label,
                        }),
                        if (error != null) Text(error!),
                        TextButton(
                          onPressed: () => setState(() {
                            draft.clear();
                            start.clear();
                            end.clear();
                            error = null;
                          }),
                          child: const Text('초기화'),
                        ),
                        const Text(
                          '기간은 한국 시간 기준이에요.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: apply,
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
