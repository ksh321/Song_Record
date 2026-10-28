import 'dart:math';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/ui_controls.dart';
import 'settings_api.dart';

class StorageView {
  StorageView(this.usage, this.slots, this.recordings) {
    for (final key in labels.keys) {
      if (usage[key] is! int || (usage[key] as int) < 0) {
        throw const FormatException('Missing storage state');
      }
    }
    if (usage['entitlement_revision'] is! int ||
        (usage['entitlement_revision'] as int) < 1) {
      throw const FormatException('Missing entitlement version');
    }
    final numbers = <int>{};
    for (final slot in slots) {
      if (slot['slot_no'] is! int ||
          (slot['slot_no'] as int) < 1 ||
          !numbers.add(slot['slot_no'] as int) ||
          slot['revision'] is! int ||
          (slot['revision'] as int) < 1 ||
          [
            slot['current_recording_id'],
            slot['pending_recording_id'],
          ].any((id) => id != null && (id is! String || !_uuid.hasMatch(id)))) {
        throw const FormatException('Invalid pin state');
      }
    }
  }
  final Map<String, dynamic> usage;
  final List<Map<String, dynamic>> slots, recordings;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static const labels = {
    'used_bytes': '사용 중',
    'reserved_bytes': '업로드 예약',
    'quota_bytes': '보관 한도',
    'trash_bytes': '휴지통 사본',
    'cleanup_pending_bytes': '정리 대기',
    'hold_bytes': '보호 중인 사본',
    'pinned_used': '고정 사용 수',
    'pinned_limit': '고정 한도',
    'pinned_pending': '고정 대기 수',
  };
  String name(Object? id) {
    if (id == null) return '없음';
    for (final row in recordings) {
      if (row['id'] == id) {
        return '${row['title_snapshot'] ?? row['title'] ?? '녹음'}';
      }
    }
    return '녹음 $id';
  }

  List<Map<String, dynamic>> get candidates => recordings
      .where(
        (r) =>
            r['metadata_state'] == 'SAVED' &&
            r['lifecycle_state'] == 'ACTIVE' &&
            r['id'] is String &&
            _uuid.hasMatch(r['id'] as String) &&
            !slots.any(
              (s) =>
                  s['current_recording_id'] == r['id'] ||
                  s['pending_recording_id'] == r['id'],
            ),
      )
      .toList();
}

String formatBytes(int bytes) {
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '$bytes B';
}

typedef PinCommand = Future<void> Function(
  String method,
  String path,
  Map<String, Object?> body,
  String operationId,
);

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    required this.load,
    required this.command,
    required this.requireCurrent,
    this.accountChanges,
    this.requestBuilder,
    this.recordingId,
    super.key,
  });
  final Future<StorageView> Function() load;
  final PinCommand command;
  final VoidCallback requireCurrent;
  final Listenable? accountChanges;
  final WidgetBuilder? requestBuilder;
  final String? recordingId;
  @override
  State<StorageScreen> createState() => _StorageState();
}

class _StorageState extends State<StorageScreen> {
  StorageView? data;
  bool busy = false;
  String? message;
  int generation = 0;
  bool dialogOpen = false;
  ({String method, String path, Map<String, Object?> body, String id})? pending;
  @override
  void initState() {
    super.initState();
    widget.accountChanges?.addListener(changed);
    refresh();
  }

  void changed() {
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
          message = '로그인 상태가 바뀌었어요. 설정 화면을 다시 열어 주세요.';
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant StorageScreen old) {
    super.didUpdateWidget(old);
    if (old.accountChanges != widget.accountChanges) {
      old.accountChanges?.removeListener(changed);
      widget.accountChanges?.addListener(changed);
    }
    if (old.load != widget.load ||
        old.requireCurrent != widget.requireCurrent) {
      pending = null;
      refresh();
    }
  }

  @override
  void dispose() {
    generation++;
    widget.accountChanges?.removeListener(changed);
    super.dispose();
  }

  Future<void> refresh() async {
    final epoch = ++generation;
    setState(() {
      busy = true;
      data = null;
    });
    try {
      widget.requireCurrent();
      final next = await widget.load();
      widget.requireCurrent();
      if (mounted && epoch == generation) {
        setState(() {
          data = next;
        });
      }
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(() {
          message = '보관 상태를 확인하지 못했어요. 새로고침해 주세요.';
        });
      }
    } finally {
      if (mounted && epoch == generation) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  String newId() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
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
      await widget.command(p.method, p.path, p.body, p.id);
      widget.requireCurrent();
      if (!mounted || epoch != generation) return;
      setState(() {
        pending = null;
        busy = false;
        message = '고정 요청이 반영됐어요. 서버 파일 용량은 정리 완료 후 바뀝니다.';
      });
      await refresh();
    } catch (e) {
      if (!mounted || epoch != generation) return;
      final definitive =
          e is SettingsUnavailable &&
          e.status != null &&
          e.status! >= 400 &&
          e.status! < 500;
      setState(() {
        busy = false;
        data = null;
        if (definitive) pending = null;
        message = definitive
            ? '최신 상태와 한도를 새로 확인해 주세요. 요청을 자동 변경하지 않습니다.'
            : '결과를 확인하지 못했어요. 같은 요청으로 다시 확인하세요.';
      });
    }
  }

  Future<void> act(
    String method,
    String path,
    Map<String, Object?> body,
    String title,
  ) async {
    final epoch = generation;
    dialogOpen = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: const Text('고정 해제·교체는 기기 파일을 삭제하지 않습니다. 서버 공간 확보를 보장하지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    dialogOpen = false;
    if (!mounted || epoch != generation || accepted != true) return;
    try {
      widget.requireCurrent();
    } catch (_) {
      changed();
      return;
    }
    pending = (
      method: method,
      path: path,
      body: Map.unmodifiable(body),
      id: newId(),
    );
    await submit();
  }

  Future<void> choose(Map<String, dynamic>? slot) async {
    final current = data;
    if (current == null) return;
    final epoch = generation;
    dialogOpen = true;
    final id = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('저장 완료 녹음 선택'),
        children: [
          for (final row in current.candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, row['id']),
              child: Text(current.name(row['id'])),
            ),
          if (current.candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('선택할 녹음이 없어요.'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    dialogOpen = false;
    if (!mounted || epoch != generation || id == null) return;
    await act(
      'POST',
      slot == null ? '/v1/pins' : '/v1/pins/${slot['slot_no']}/replacement',
      {
        'recording_id': id,
        if (slot == null)
          'entitlement_revision': current.usage['entitlement_revision']
        else
          'base_revision': slot['revision'],
      },
      slot == null ? '고정 신청' : '고정 교체',
    );
  }

  Widget focusedRecording(StorageView current) {
    final id = widget.recordingId!;
    final matches = current.slots.where(
      (slot) =>
          slot['current_recording_id'] == id ||
          slot['pending_recording_id'] == id,
    );
    final slot = matches.firstOrNull;
    final available = current.candidates.any((row) => row['id'] == id);
    final full =
        (current.usage['pinned_used'] as int) >=
        (current.usage['pinned_limit'] as int);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          current.name(id),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        if (slot != null) ...[
          Text(slot['pending_recording_id'] == id ? '고정 보관 대기 중' : '고정 보관 중'),
          FilledButton(
            onPressed: busy || pending != null
                ? null
                : () => act(
                    slot['current_recording_id'] != null &&
                            slot['pending_recording_id'] == id
                        ? 'POST'
                        : 'DELETE',
                    slot['current_recording_id'] != null &&
                            slot['pending_recording_id'] == id
                        ? '/v1/pins/${slot['slot_no']}/replacement/cancel'
                        : '/v1/pins/${slot['slot_no']}',
                    {'base_revision': slot['revision']},
                    '고정 해제',
                  ),
            child: const Text('고정 해제'),
          ),
        ] else ...[
          if (full) const Text('고정 보관 한도가 찼어요. 보관량과 고정에서 기존 고정을 변경해 주세요.'),
          if (!available) const Text('고정할 녹음을 확인하지 못했어요. 최신 상태를 확인해 주세요.'),
          FilledButton(
            onPressed: busy || pending != null || full || !available
                ? null
                : () => act('POST', '/v1/pins', {
                    'recording_id': id,
                    'entitlement_revision':
                        current.usage['entitlement_revision'],
                  }, '고정 신청'),
            child: const Text('고정 보관'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(
      context,
      title: Text(widget.recordingId == null ? '보관량과 고정' : '녹음 고정 보관'),
      actions: [
        IconButton(
          tooltip: '새로고침',
          onPressed: busy || pending != null ? null : refresh,
          icon: const AppIcon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          if (pending != null)
            FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('같은 요청 결과 다시 확인'),
            ),
          if (data != null && widget.recordingId != null)
            focusedRecording(data!),
          if (data case final current? when widget.recordingId == null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '서버 보관량',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatBytes(
                              current.usage['used_bytes'] as int,
                            ),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' / ${formatBytes(current.usage['quota_bytes'] as int)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: (current.usage['quota_bytes'] as int) == 0
                          ? 0
                          : ((current.usage['used_bytes'] as int) /
                                    (current.usage['quota_bytes'] as int))
                                .clamp(0.0, 1.0),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .14),
                      semanticsLabel: '서버 보관량',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '고정 보관 ${current.usage['pinned_used']} / ${current.usage['pinned_limit']}개 · 업로드 대기 ${formatBytes(current.usage['reserved_bytes'] as int)}',
                    ),
                  ],
                ),
              ),
            ),
            if (current.usage['waiting_by_reason'] is Map)
              for (final waiting
                  in (current.usage['waiting_by_reason'] as Map).entries)
                if (waiting.value is int && (waiting.value as int) > 0)
                  Text(
                    '${const {'PIN_LIMIT': '고정 개수 부족', 'USER_QUOTA': '계정 보관 용량 부족', 'GLOBAL_QUOTA': '서비스 보관 용량 대기', 'QUOTA': '보관 용량 부족', 'WAITING_LOCAL_CONFIRM': '기기 보존 확인 대기'}[waiting.key] ?? '다른 보관 대기'}: ${waiting.value}개',
                  ),
            if (widget.requestBuilder != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: widget.requestBuilder!,
                        ),
                      ),
                child: const Text('추가 보관 요청'),
              ),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ExpansionTile(
                    leading: const FeatureIcon(
                      Icons.push_pin_outlined,
                      size: 34,
                    ),
                    title: const Text('고정한 녹음'),
                    subtitle: const Text('중요한 녹음을 계속 보관'),
                    childrenPadding: const EdgeInsets.all(14),
                    children: [
                      FilledButton(
                        onPressed:
                            busy ||
                                pending != null ||
                                (current.usage['pinned_used'] as int) >=
                                    (current.usage['pinned_limit'] as int)
                            ? null
                            : () => choose(null),
                        child: const Text('녹음 고정 신청'),
                      ),
                      for (final slot in current.slots)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '고정 ${slot['slot_no']} · 현재 ${current.name(slot['current_recording_id'])}',
                                ),
                                if (slot['pending_recording_id'] != null)
                                  Text(
                                    '${slot['current_recording_id'] == null ? '고정 대기' : '교체 대기'}: ${current.name(slot['pending_recording_id'])}',
                                  ),
                                Wrap(
                                  children: [
                                    if (slot['current_recording_id'] != null &&
                                        slot['pending_recording_id'] == null)
                                      TextButton(
                                        onPressed: busy || pending != null
                                            ? null
                                            : () => choose(slot),
                                        child: const Text('교체'),
                                      ),
                                    if (slot['current_recording_id'] != null &&
                                        slot['pending_recording_id'] != null)
                                      TextButton(
                                        onPressed: busy || pending != null
                                            ? null
                                            : () => act(
                                                'POST',
                                                '/v1/pins/${slot['slot_no']}/replacement/cancel',
                                                {
                                                  'base_revision':
                                                      slot['revision'],
                                                },
                                                '교체 대기 취소',
                                              ),
                                        child: const Text('교체 대기 취소'),
                                      ),
                                    TextButton(
                                      onPressed: busy || pending != null
                                          ? null
                                          : () => act(
                                              'DELETE',
                                              '/v1/pins/${slot['slot_no']}',
                                              {
                                                'base_revision':
                                                    slot['revision'],
                                              },
                                              '고정 해제',
                                            ),
                                      child: Text(
                                        slot['current_recording_id'] == null
                                            ? '고정 대기 취소'
                                            : '고정 해제',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 1),
                  ExpansionTile(
                    leading: const FeatureIcon(
                      Icons.storage_outlined,
                      size: 34,
                    ),
                    title: const Text('서버 사본 정리'),
                    subtitle: const Text('이 기기의 원본은 유지'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '정리 대기 ${formatBytes(current.usage['cleanup_pending_bytes'] as int)} · 휴지통 ${formatBytes(current.usage['trash_bytes'] as int)}. 서버 정리가 끝난 뒤 보관량에 반영돼요. 공간 확보를 약속할 수는 없어요.',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const ExpansionTile(
                    leading: FeatureIcon(Icons.queue_music_outlined, size: 34),
                    title: Text('자동 보관 기준'),
                    subtitle: Text('대표 · 최신 · 최저 티어'),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          '대표·최신·최저 티어 녹음을 자동 보관해요. 같은 녹음이 여러 역할을 맡으면 한 번만 세어요.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
              title: const Text('사용량 자세히 보기'),
              children: [
                for (final field in StorageView.labels.entries)
                  ListTile(
                    title: Text(field.value),
                    trailing: Text(
                      field.key.endsWith('_bytes')
                          ? formatBytes(current.usage[field.key] as int)
                          : '${current.usage[field.key]}개',
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '휴지통·정리 대기·보호 중인 사본은 사용 중 용량에 포함되며 서로 겹칠 수 있어요. 고정을 해제해도 용량은 즉시 줄지 않아요.',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
