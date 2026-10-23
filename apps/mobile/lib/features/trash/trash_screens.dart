import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';
import '../auth/auth_session.dart';
import 'trash_workflow.dart';

String trashError(Object error) => error is TrashFailure
    ? error.message
    : '확인하지 못했어요. 원본 파일은 유지돼요. 다시 확인해 주세요.';

class DeleteScreen extends StatefulWidget {
  const DeleteScreen({
    required this.actions,
    required this.id,
    required this.title,
    this.recording = false,
    this.auth,
    super.key,
  });
  final TrashActions actions;
  final String id, title;
  final bool recording;
  final AuthController? auth;
  @override
  State<DeleteScreen> createState() => _DeleteScreenState();
}

class _DeleteScreenState extends State<DeleteScreen> {
  Map<String, dynamic>? preview;
  String? error, message;
  bool loading = false, invalid = false, confirmed = false;
  String mode = 'SONG_ONLY';
  late final scope =
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(accountChanged);
    if (!widget.recording) load();
  }

  void accountChanged() {
    if (scope !=
            '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}' &&
        mounted) {
      setState(() => invalid = true);
    }
  }

  @override
  void dispose() {
    widget.auth?.removeListener(accountChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (loading || invalid) return;
    setState(() {
      loading = true;
      error = null;
      preview = null;
    });
    try {
      final result = await widget.actions.preview(widget.id);
      if (mounted && !invalid) setState(() => preview = result);
    } catch (e) {
      if (mounted && !invalid) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (loading || invalid || message != null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.recording) {
        await widget.actions.trashRecording(widget.id, confirmed);
      } else {
        await widget.actions.trashSong(
          widget.id,
          mode,
          preview!['preview_version'] as String,
        );
      }
      if (mounted && !invalid) {
        setState(
          () =>
              message = '삭제 동기화 대기 · 원본 파일은 유지돼요. 서버 확정 시각부터 7일 동안 복원할 수 있어요.',
        );
      }
    } catch (e) {
      if (mounted && !invalid) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.recording ? '녹음 삭제' : '곡 삭제')),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (invalid)
            const Text('계정이 변경됐어요. 목록에서 다시 열어 주세요.')
          else if (message != null)
            Text(message!)
          else ...[
            const Text(
              '서버가 확정한 삭제 시각부터 7일 동안 휴지통에 보관돼요. 기기 시각만으로 원본 파일을 지우지 않아요.',
            ),
            if (widget.recording) ...[
              const Text('녹음 삭제 시 고정 슬롯이 해제돼요. 복원해도 고정·대표는 자동으로 돌아오지 않아요.'),
              CheckboxListTile(
                value: confirmed,
                onChanged: loading
                    ? null
                    : (v) => setState(() => confirmed = v ?? false),
                title: const Text('고정 해제를 확인했어요'),
              ),
            ] else ...[
              if (preview != null) ...[
                Text(
                  '서버 연결 녹음 ${preview!['recording_count']}개 · 서버 파일 ${preview!['server_bytes']}바이트 · 고정 ${preview!['pinned_count']}개',
                ),
                const Text('다른 기기의 아직 전송하지 않은 녹음은 포함하지 않아요.'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'SONG_ONLY', label: Text('녹음 유지')),
                    ButtonSegment(
                      value: 'SONG_AND_RECORDINGS',
                      label: Text('함께 삭제'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: loading
                      ? null
                      : (v) => setState(() => mode = v.first),
                ),
                Text(
                  mode == 'SONG_ONLY'
                      ? '곡만 삭제하고 녹음 유지: 녹음은 미연결로 남고 파일·기존 고정은 유지돼요.'
                      : '곡과 녹음 함께 삭제: 현재 연결 녹음도 휴지통으로 이동하고 고정이 해제돼요.',
                ),
              ],
              if (preview == null && !loading)
                TextButton(
                  onPressed: load,
                  child: const Text('서버 삭제 정보 다시 확인'),
                ),
            ],
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            FilledButton(
              onPressed:
                  loading || (widget.recording ? !confirmed : preview == null)
                  ? null
                  : save,
              child: const Text('휴지통으로 이동'),
            ),
          ],
          TextButton(
            onPressed: loading ? null : () => Navigator.of(context).pop(),
            child: Text(message == null ? '취소' : '돌아가기'),
          ),
        ],
      ),
    ),
  );
}

class TrashScreen extends StatefulWidget {
  const TrashScreen({required this.actions, this.auth, super.key});
  final TrashActions actions;
  final AuthController? auth;
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<TrashBatch> batches = [];
  String? cursor, error, message;
  bool loading = false, invalid = false;
  Map<String, dynamic>? pending;
  late final scope =
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(changed);
    load();
  }

  void changed() {
    if (scope !=
            '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}' &&
        mounted) {
      setState(() {
        invalid = true;
        batches = [];
        pending = null;
        message = null;
      });
    }
  }

  @override
  void dispose() {
    widget.auth?.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool more = false, bool clearError = true}) async {
    if (loading || invalid) return;
    setState(() {
      loading = true;
      if (clearError) error = null;
    });
    try {
      final saved = await widget.actions.pending();
      if (mounted && !invalid) setState(() => pending = saved);
      final page = await widget.actions.page(more ? cursor : null);
      final rows = (page['items'] as List)
          .map((v) => TrashBatch.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
      if (mounted && !invalid) {
        setState(() {
          if (!more) batches = [];
          for (final row in rows) {
            if (!batches.any((b) => b.id == row.id)) batches.add(row);
          }
          cursor = page['next_cursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted && !invalid) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> act(TrashBatch batch, bool purge) async {
    final selected = <String>{};
    final choices = batch.items
        .where(
          (v) =>
              v['entity_type'] != 'PLAYLIST_ITEM' &&
              (v['state'] == null || v['state'] == 'TRASHED'),
        )
        .toList();
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  purge ? '영구 삭제 확인' : '복원할 항목 선택',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  purge ? '선택한 항목은 복원할 수 없어요. 보존한 활성 녹음은 곡 영구 삭제로 지워지지 않아요.' : '같은 삭제 묶음에서 가능한 항목만 복원해요. 변경된 연결은 덮어쓰지 않아요. 고정·대표는 다시 선택해 주세요.',
                ),
                for (final item in choices)
                  CheckboxListTile(
                    title: Text(
                      '${item['entity_type'] == 'SONG' ? '곡' : '녹음'} · ${item['title'] ?? item['id']}',
                    ),
                    value: selected.contains(item['id']),
                    onChanged: (v) => change(() {
                      if (v == true) {
                        selected.add(item['id'] as String);
                      } else {
                        selected.remove(item['id']);
                      }
                    }),
                  ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected.toList()),
                  child: Text(purge ? '선택 항목 영구 삭제' : '선택 항목 복원'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ids == null || !mounted || invalid || loading) return;
    setState(() {
      loading = true;
      error = null;
      message = null;
    });
    try {
      final result = await widget.actions.mutate(batch, ids, purge);
      if (mounted && !invalid) {
        setState(() {
          if (purge) {
            message =
                '영구 삭제 처리 중 · 파일 삭제 확인 후 완료돼요. 실패하면 원본·용량을 확정하지 않고 재시도해요.';
          } else {
            message =
                '${(result['restored'] as List).length}개 복원 · ${(result['skipped'] as List).length}개 제외. 변경된 연결·이미 복원된 항목·삭제된 목록은 덮어쓰지 않아요. 고정은 다시 선택해야 함. 대표도 다시 지정해 주세요.';
          }
        });
      }
    } catch (e) {
      if (mounted && !invalid) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && !invalid) await load(clearError: false);
  }

  Future<void> retry() async {
    setState(() {
      loading = true;
      error = null;
      message = null;
    });
    try {
      final result = await widget.actions.retry();
      if (mounted && !invalid) {
        setState(
          () => message = result['state'] == 'PURGE_PENDING'
              ? '영구 삭제 처리 중 · 완료는 서버 동기화로 확인해 주세요.'
              : '복원 결과 확인 완료 · 고정은 다시 선택해야 함.',
        );
      }
    } catch (e) {
      if (mounted && !invalid) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && !invalid) await load(clearError: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('휴지통'),
      actions: [
        IconButton(
          tooltip: '새로 확인',
          onPressed: loading || invalid ? null : load,
          icon: const AppIcon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          if (invalid)
            const Text('계정이 변경됐어요. 다시 열어 주세요.')
          else ...[
            const Text('서버 삭제 시각부터 7일 · 대표·고정은 자동 복원되지 않아요.'),
            if (message != null) Text(message!),
            if (error != null)
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            if (loading) const LinearProgressIndicator(),
            if (pending != null)
              FilledButton(
                onPressed: loading ? null : retry,
                child: const Text('결과 미확인 요청 다시 확인'),
              ),
            if (batches.isEmpty && !loading && error == null)
              const Text('휴지통이 비어 있어요. 삭제 동기화 대기는 동기화 상태에서 확인해 주세요.'),
            for (final batch in batches)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.mode == 'SONG_ONLY'
                            ? '곡만 삭제 · 녹음 유지'
                            : batch.mode == 'RECORDING'
                            ? '녹음 삭제'
                            : '곡과 녹음 함께 삭제',
                      ),
                      Text(
                        '서버 삭제: ${batch.deleted.toLocal()}\n서버 만료: ${batch.expires.toLocal()}',
                      ),
                      if (batch.items.any((v) => v['state'] == 'PURGE_PENDING'))
                        const Text('영구 삭제 처리 중'),
                      if (batch.items.any(
                        (v) =>
                            v['entity_type'] != 'PLAYLIST_ITEM' &&
                            (v['state'] == null || v['state'] == 'TRASHED'),
                      ))
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: loading || pending != null
                                  ? null
                                  : () => act(batch, false),
                              child: const Text('복원'),
                            ),
                            TextButton(
                              onPressed: loading || pending != null
                                  ? null
                                  : () => act(batch, true),
                              child: const Text('영구 삭제'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (cursor != null)
              TextButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('더 보기'),
              ),
          ],
        ],
      ),
    ),
  );
}
