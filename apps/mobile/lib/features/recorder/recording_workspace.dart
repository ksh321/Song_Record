import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_tokens.dart';

import 'recorder_gateway.dart';
import 'recorder_panel.dart';
import 'recording_input_screen.dart';
import 'recording_song_picker.dart';

class RecordingWorkspace extends StatefulWidget {
  const RecordingWorkspace({
    required this.gateway,
    required this.repository,
    required this.isCurrent,
    this.wakeSync,
    this.discoveryBuilder,
    super.key,
  });
  final RecorderGateway gateway;
  final LocalRepository? Function() repository;
  final bool Function(LocalRepository) isCurrent;
  final VoidCallback? wakeSync;
  final RecordingDiscoveryBuilder? discoveryBuilder;
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

  Future<void> _persist(RecorderStatus status) async {
    final repo = widget.repository();
    final gateway = widget.gateway;
    if (repo == null ||
        !widget.isCurrent(repo) ||
        gateway is! CompletedRecordingGateway ||
        status.recordingId == null) {
      throw StateError('Capture handoff unavailable');
    }
    final source = await (gateway as CompletedRecordingGateway).readCompleted(
      status.recordingId!,
    );
    if (!mounted ||
        !widget.isCurrent(repo) ||
        source['recordingId'] != status.recordingId ||
        source['phase'] != 'completed') {
      throw StateError('Capture account changed');
    }
    final file = <String, dynamic>{
      'sha256': source['sha256'],
      'size_bytes': source['sizeBytes'],
      'duration_ms': source['durationMs'],
      'codec': 'AAC_LC',
      'sample_rate': source['actualSampleRate'],
      'channels': source['actualChannels'],
      'capture_integrity': source['recovered'] == true
          ? 'RECOVERED'
          : 'VALIDATED',
    };
    if (source['actualMime'] != 'audio/mp4a-latm' ||
        source['actualAacProfile'] != 2 ||
        source['bytes'] is! Uint8List) {
      throw StateError('Unverified audio format');
    }
    await repo.importCompletedCapture(
      accountScope: source['accountScope'] as String,
      recordingId: status.recordingId!,
      bytes: source['bytes'] as Uint8List,
      fileSpec: file,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (source['startedAtWallClockMs'] as num).toInt(),
        isUtc: true,
      ),
      timezoneId: source['timezoneId'] as String,
      timezoneOffsetMinutes: (source['timezoneOffsetMinutes'] as num).toInt(),
    );
    if (!mounted || !widget.isCurrent(repo)) {
      throw StateError('Capture account changed');
    }
    widget.wakeSync?.call();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.lg),
    children: [
      RecorderPanel(
        gateway: widget.gateway,
        diagnostics: false,
        onCompleted: _persist,
      ),
      const SizedBox(height: AppSpacing.lg),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _pending,
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
                  title: Text(
                    (row['title_snapshot'] as String?) ?? '곡 정보 입력 대기',
                  ),
                  subtitle: Text(
                    row['input_selection'] is Map
                        ? '선택한 곡: ${row['input_selection']['title_snapshot']}'
                        : '정보 입력 대기 · ${row['recorded_at']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final repo = widget.repository();
                    if (repo == null || !widget.isCurrent(repo)) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => RecordingInputScreen(
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
      ),
    ],
  );
}
