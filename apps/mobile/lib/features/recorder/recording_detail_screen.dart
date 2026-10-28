import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/database/local_models.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/detail_information_card.dart';
import '../../core/widgets/ui_controls.dart';
import '../songs/my_song_detail.dart';
import '../trash/trash_screens.dart';
import '../trash/trash_workflow.dart';
import 'recording_input_screen.dart';
import 'recording_manage_screen.dart';
import 'recording_relink_screen.dart';

class RecordingDetailScreen extends StatefulWidget {
  const RecordingDetailScreen({
    required this.id,
    required this.repository,
    required this.isCurrent,
    this.wakeSync,
    this.classificationBuilder,
    this.trash,
    super.key,
  });
  final String id;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final VoidCallback? wakeSync;
  final WidgetBuilder? classificationBuilder;
  final TrashActions? trash;
  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  late Future<MetadataCopy?> future = widget.repository.read(
    LocalEntity.recording,
    widget.id,
  );
  Future<void> edit(
    Map<String, dynamic> row,
    int revision, [
    String? field,
  ]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingInputScreen(
          classificationBuilder: widget.classificationBuilder,
          recording: row,
          repository: widget.repository,
          isCurrent: widget.isCurrent,
          wakeSync: widget.wakeSync,
          editing: true,
          revision: revision,
          initialField: field,
        ),
      ),
    );
    if (mounted && widget.isCurrent(widget.repository)) {
      setState(() {
        future = widget.repository.read(LocalEntity.recording, widget.id);
      });
    }
  }

  void refresh() {
    if (mounted && widget.isCurrent(widget.repository)) {
      setState(() {
        future = widget.repository.read(LocalEntity.recording, widget.id);
      });
    }
  }

  Future<void> relink(Map<String, dynamic> row, int revision) async {
    if (!widget.isCurrent(widget.repository)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingRelinkScreen(
          recording: row,
          revision: revision,
          repository: widget.repository,
          isCurrent: widget.isCurrent,
          wakeSync: widget.wakeSync,
        ),
      ),
    );
    refresh();
  }

  Widget deleteScreen(Map<String, dynamic> row) => DeleteScreen(
    actions: widget.trash!,
    id: widget.id,
    title: row['title_snapshot'] as String,
    recording: true,
  );

  Future<void> menu(
    String action,
    Map<String, dynamic> row,
    int revision,
  ) async {
    if (!mounted || !widget.isCurrent(widget.repository)) return;
    if (action == 'edit') {
      await edit(row, revision);
      return;
    }
    if (action == 'delete' && widget.trash == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => action == 'delete'
            ? deleteScreen(row)
            : RecordingManageScreen(
                id: widget.id,
                title: row['title_snapshot'] as String,
                artist: row['artist_snapshot'] as String,
                isCurrent: () => widget.isCurrent(widget.repository),
                deleteBuilder: widget.trash == null
                    ? null
                    : (_) => deleteScreen(row),
              ),
      ),
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('녹음 상세')),
    body: SafeArea(
      child: FutureBuilder<MetadataCopy?>(
        future: future,
        builder: (context, snapshot) {
          if (!widget.isCurrent(widget.repository)) {
            return const Center(child: Text('계정이 변경됐어요. 다시 열어 주세요.'));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('녹음 정보를 확인하지 못했어요.'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final copy = snapshot.data,
              raw = snapshot.data?.localJson ?? snapshot.data?.serverJson;
          if (copy == null || copy.tombstone || raw == null) {
            return const Center(child: Text('녹음 정보를 찾을 수 없어요.'));
          }
          final row = jsonDecode(raw) as Map<String, dynamic>;
          if (row['metadata_state'] != 'SAVED' ||
              row['lifecycle_state'] != 'ACTIVE') {
            return const Center(child: Text('활성 저장 녹음이 아니에요.'));
          }
          final view = MySongDetail.recordingView(row);
          final tags = (row['tags'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map((t) => t['name_snapshot'])
              .join(', ');
          return ListView(
            padding: AppLayout.bodyPadding,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 12,
                ),
                child: Column(
                  children: [
                    Text(
                      view.snapshot.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      view.snapshot.artist,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.8,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${view.dateLabel} · ${view.durationLabel}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.8,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<String>(
                  tooltip: '녹음 메뉴',
                  icon: const AppIcon(Icons.more_vert),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('정보 수정')),
                    const PopupMenuItem(value: 'manage', child: Text('보관 관리')),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: widget.trash != null,
                      child: const Text('삭제'),
                    ),
                  ],
                  onSelected: (action) => menu(action, row, copy.revision),
                ),
              ),
              const SizedBox(height: 14),
              DetailInformationCard(
                title: '녹음 정보',
                fields: [
                  ('버전', formatVersionCode(view.snapshot.version)),
                  ('키', formatMusicalKey(view.snapshot.key)),
                  ('녹음 티어', row['tier'] as String? ?? '미정'),
                ],
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('컨디션과 태그', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text('컨디션: ${row['condition_name_snapshot'] ?? '미선택'}'),
                    Text('태그: ${tags.isEmpty ? '없음' : tags}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('메모', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      (row['note'] as String? ?? '').isEmpty
                          ? '아직 작성하지 않았어요.'
                          : row['note'] as String,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('연결 곡', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(row['song_id'] == null ? '곡 미연결 녹음' : '등록된 내 곡에 연결됨'),
                    TextButton(
                      onPressed: () => relink(row, copy.revision),
                      child: const Text('곡 연결 변경'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
