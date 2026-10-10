import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/local_models.dart';
import '../../core/domain/song_types.dart';
import '../../core/sync/local_repository.dart';
import '../../core/theme/app_tokens.dart';
import 'recording_input_screen.dart';
import 'recording_relink_screen.dart';

class RecordingDetailScreen extends StatefulWidget {
  const RecordingDetailScreen({
    required this.id,
    required this.repository,
    required this.isCurrent,
    this.wakeSync,
    super.key,
  });
  final String id;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final VoidCallback? wakeSync;
  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  late Future<MetadataCopy?> future = widget.repository.read(
    LocalEntity.recording,
    widget.id,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('녹음 상세')),
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                row['title_snapshot'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(row['artist_snapshot'] as String),
              Text(
                '키: ${formatMusicalKey(MusicalKey(mode: KeyMode.values.firstWhere((k) => k.name.toUpperCase() == row['key_mode']), shift: row['key_shift'] as int))} · 버전: ${formatVersionCode(VersionCode.values.firstWhere((v) => v.name.toUpperCase() == row['version_code']))}',
              ),
              Text('녹음 티어: ${row['tier'] ?? '미정'}'),
              Text('녹음 시각: ${row['recorded_at']}'),
              Text('컨디션: ${row['condition_name_snapshot'] ?? '미선택'}'),
              Text(
                '태그: ${(row['tags'] as List? ?? []).whereType<Map<String, dynamic>>().map((t) => t['name_snapshot']).join(', ')}',
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
              const Text('녹음 당시 메모'),
              Text(row['note'] as String? ?? ''),
              FilledButton(
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordingInputScreen(
                        recording: row,
                        repository: widget.repository,
                        isCurrent: widget.isCurrent,
                        wakeSync: widget.wakeSync,
                        editing: true,
                        revision: copy.revision,
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
                child: const Text('녹음 정보 수정'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
