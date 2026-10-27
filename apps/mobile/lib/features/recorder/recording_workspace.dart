import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/files/recording_catalog.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';
import '../trash/trash_screens.dart';
import '../trash/trash_workflow.dart';
import 'completed_capture_handoff.dart';
import 'recorder_gateway.dart';
import 'recorder_panel.dart';
import 'recording_detail_screen.dart';
import 'recording_input_screen.dart';
import 'recording_list.dart';
import 'recording_song_picker.dart';

class RecordingWorkspace extends StatefulWidget {
  const RecordingWorkspace({
    required this.gateway,
    required this.repository,
    required this.isCurrent,
    this.wakeSync,
    this.classificationBuilder,
    this.discoveryBuilder,
    this.trash,
    super.key,
  });
  final RecorderGateway gateway;
  final LocalRepository? Function() repository;
  final bool Function(LocalRepository) isCurrent;
  final VoidCallback? wakeSync;
  final WidgetBuilder? classificationBuilder;
  final RecordingDiscoveryBuilder? discoveryBuilder;
  final TrashActions? trash;
  @override
  State<RecordingWorkspace> createState() => _RecordingWorkspaceState();
}

class _RecordingWorkspaceState extends State<RecordingWorkspace> {
  late final Stream<List<Map<String, dynamic>>> _pending = _watch();
  Stream<List<Map<String, dynamic>>> _watch() async* {
    while (mounted) {
      final repo = widget.repository();
      if (repo == null || !widget.isCurrent(repo)) {
        throw StateError('Active account required');
      }
      final records = await repo.pendingRecordings();
      if (!mounted || !widget.isCurrent(repo)) return;
      yield records;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Stream<RecordingCatalog> _watchSaved() async* {
    while (mounted) {
      final repo = widget.repository();
      if (repo == null || !widget.isCurrent(repo)) {
        throw StateError('Active account required');
      }
      final snapshot = await repo.recordingCatalog();
      if (!mounted || !widget.isCurrent(repo)) return;
      yield snapshot;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _persist(RecorderStatus status) async {
    final repo = widget.repository();
    final gateway = widget.gateway;
    if (repo == null ||
        !widget.isCurrent(repo) ||
        gateway is! CompletedRecordingGateway ||
        status.recordingId == null) {
      throw StateError('Capture handoff unavailable');
    }
    await preserveCompletedCapture(
      status: status,
      gateway: gateway as CompletedRecordingGateway,
      repository: repo,
      requireCurrent: () {
        if (!mounted || !widget.isCurrent(repo)) {
          throw StateError('Capture account changed');
        }
      },
    );
    widget.wakeSync?.call();
  }

  Widget _entry(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback open,
  ) => Card(
    child: AppFeatureRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: open,
      grouped: false,
    ),
  );

  void _open(String title, Widget body) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: appPageBar(context, title: Text(title)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: AppLayout.bodyPadding,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: AppLayout.bodyPadding,
    children: [
      RecorderPanel(
        gateway: widget.gateway,
        diagnostics: false,
        onCompleted: _persist,
      ),
      const SizedBox(height: 20),
      Text(
        '한 번에 최대 6분',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 60),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _pending,
        builder: (context, snapshot) => _entry(
          '입력 대기',
          snapshot.hasError
              ? '목록을 다시 확인해 주세요'
              : snapshot.hasData
              ? '곡 정보를 기다리는 녹음 ${snapshot.data!.length}개'
              : '목록 확인 중',
          Icons.schedule,
          () => _open('입력 대기', _pendingList()),
        ),
      ),
      _entry(
        '전체 녹음',
        '지난 녹음 다시 듣기',
        Icons.graphic_eq,
        () => _open('전체 녹음', _savedList()),
      ),
    ],
  );

  Widget _pendingList() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: _watch(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('입력 대기 목록을 확인하지 못했어요. 계정 상태를 확인해 주세요.');
      }
      if (!snapshot.hasData) return const Text('입력 대기 확인 중');
      final rows = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('입력 대기 ${rows.length}개'),
          for (final row in rows)
            ListTile(
              title: Text((row['title_snapshot'] as String?) ?? '곡 정보 입력 대기'),
              subtitle: Text(
                row['input_selection'] is Map
                    ? '선택한 곡: ${row['input_selection']['title_snapshot']}'
                    : '정보 입력 대기 · ${row['recorded_at']}',
              ),
              trailing: const AppIcon(Icons.chevron_right),
              onTap: () {
                final repo = widget.repository();
                if (repo == null || !widget.isCurrent(repo)) return;
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => RecordingInputScreen(
                      classificationBuilder: widget.classificationBuilder,
                      recording: row,
                      repository: repo,
                      isCurrent: widget.isCurrent,
                      discoveryBuilder: widget.discoveryBuilder,
                      wakeSync: widget.wakeSync,
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );

  Widget _savedList() => StreamBuilder<RecordingCatalog>(
    stream: _watchSaved(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('저장 목록을 확인하지 못했어요.');
      if (!snapshot.hasData) return const Text('저장 녹음 확인 중');
      return RecordingList(
        rows: snapshot.data!.rows,
        scope: snapshot.data!.scope,
        metadataComplete: snapshot.data!.complete,
        lastSync: snapshot.data!.lastSync,
        onDelete: widget.trash == null
            ? null
            : (row) {
                final repo = widget.repository();
                if (repo == null || !widget.isCurrent(repo)) return;
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeleteScreen(
                      actions: widget.trash!,
                      id: row['id'] as String,
                      title: row['title_snapshot'] as String? ?? '녹음',
                      recording: true,
                    ),
                  ),
                );
              },
        onOpen: (row) {
          final repo = widget.repository();
          if (repo == null || !widget.isCurrent(repo)) return;
          Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => RecordingDetailScreen(
                classificationBuilder: widget.classificationBuilder,
                trash: widget.trash,
                id: row['id'] as String,
                repository: repo,
                isCurrent: widget.isCurrent,
                wakeSync: widget.wakeSync,
              ),
            ),
          );
        },
      );
    },
  );
}
