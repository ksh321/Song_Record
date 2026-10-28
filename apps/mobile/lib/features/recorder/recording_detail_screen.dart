import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/database/local_models.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/ui_controls.dart';
import '../songs/my_song_detail.dart';
import '../trash/trash_screens.dart';
import '../trash/trash_workflow.dart';
import 'recording_audio_panel.dart';
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
      setState(
        () => future = widget.repository.read(LocalEntity.recording, widget.id),
      );
    }
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
          final copy = snapshot.data;
          final raw = copy?.localJson ?? copy?.serverJson;
          if (copy == null || copy.tombstone || raw == null) {
            return const Center(child: Text('녹음 정보를 찾을 수 없어요.'));
          }
          final row = jsonDecode(raw) as Map<String, dynamic>;
          if (row['metadata_state'] != 'SAVED' ||
              row['lifecycle_state'] != 'ACTIVE') {
            return const Center(child: Text('활성 저장 녹음이 아니에요.'));
          }
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
                    const FeatureIcon(Icons.music_note_outlined),
                    const SizedBox(height: 16),
                    Text(
                      row['title_snapshot'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${row['artist_snapshot']} · ${MySongDetail.recordingView(row).dateLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AppPickerField(
                label: '버전',
                value: formatVersionCode(
                  VersionCode.values.firstWhere(
                    (v) => v.name.toUpperCase() == row['version_code'],
                  ),
                ),
                onPressed: () => edit(row, copy.revision, 'version'),
              ),
              AppPickerField(
                label: '키',
                value: formatMusicalKey(
                  MusicalKey(
                    mode: KeyMode.values.firstWhere(
                      (k) => k.name.toUpperCase() == row['key_mode'],
                    ),
                    shift: row['key_shift'] as int,
                  ),
                ),
                onPressed: () => edit(row, copy.revision, 'key'),
              ),
              AppPickerField(
                label: '녹음 티어',
                value: row['tier'] as String? ?? '미정',
                onPressed: () => edit(row, copy.revision, 'tier'),
              ),
              RecordingAudioPanel(
                widget.id,
                compact: true,
                showPlayback: false,
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('컨디션과 태그', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text('컨디션: ${row['condition_name_snapshot'] ?? '미선택'}'),
                    Text(
                      '태그: ${(row['tags'] as List? ?? []).whereType<Map<String, dynamic>>().map((t) => t['name_snapshot']).join(', ')}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('연습 메모', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      (row['note'] as String? ?? '').isEmpty
                          ? '아직 작성하지 않았어요.'
                          : row['note'] as String,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => edit(row, copy.revision),
                child: const Text('녹음 정보 수정'),
              ),
              Text(row['song_id'] == null ? '곡 미연결 녹음' : '등록된 내 곡에 연결됨'),
              TextButton(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordingRelinkScreen(
                        recording: row,
                        revision: copy.revision,
                        repository: widget.repository,
                        isCurrent: widget.isCurrent,
                        wakeSync: widget.wakeSync,
                      ),
                    ),
                  );
                  if (mounted && widget.isCurrent(widget.repository)) {
                    setState(
                      () => future = widget.repository.read(
                        LocalEntity.recording,
                        widget.id,
                      ),
                    );
                  }
                },
                child: const Text('곡 연결 변경'),
              ),
              RecordingAudioPanel(widget.id, showStatus: false),
              OutlinedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordingManageScreen(
                      id: widget.id,
                      title: row['title_snapshot'] as String,
                      artist: row['artist_snapshot'] as String,
                      isCurrent: () => widget.isCurrent(widget.repository),
                      deleteBuilder: widget.trash == null
                          ? null
                          : (_) => DeleteScreen(
                              actions: widget.trash!,
                              id: widget.id,
                              title: row['title_snapshot'] as String,
                              recording: true,
                            ),
                    ),
                  ),
                ),
                child: const Text('보관·삭제 관리'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
