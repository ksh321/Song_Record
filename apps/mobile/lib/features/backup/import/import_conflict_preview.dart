import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ui_controls.dart';
import 'import_conflicts.dart';

String _entity(String entity) => switch (entity) {
  'SONG' => '곡',
  'RECORDING' => '녹음',
  'PLAYLIST' => '플레이리스트',
  'TAG' => '태그',
  'RECORDING_CONDITION' => '컨디션',
  _ => '기록',
};

String _reason(String code) => switch (code) {
  'LOCAL_FILE_CHECKSUM_CONFLICT' => '이 기기의 녹음 파일과 백업 파일의 내용이 달라요.',
  'BACKUP_FILE_DESCRIPTION_MISMATCH' ||
  'SERVER_FILE_DESCRIPTION_MISMATCH' => '녹음 파일이 저장된 정보와 일치하지 않아요.',
  'RECORDING_LINK_CONFLICT' => '이 녹음이 연결된 곡이 서로 달라요.',
  'IMPORT_OPERATION_REVIEW' => '백업에 그대로 적용할 수 없는 변경 사항이 있어요.',
  'INVALID_OR_NEWER_BASELINE' => '백업과 현재 기록 중 어떤 내용이 최신인지 확인하지 못했어요.',
  _ => '백업과 현재 기록의 내용이 달라요.',
};

// Only display understandable user fields. Internal IDs, hashes and operation
// payloads remain in the preserved comparison, never in the visible summary.
String _summary(Object? value) {
  if (value is! Map) return '비교할 정보 없음';
  const labels = {
    'title': '곡명',
    'title_snapshot': '곡명',
    'artist': '가수',
    'artist_snapshot': '가수',
    'name': '이름',
    'note': '메모',
    'tier': '티어',
  };
  final parts = <String>[
    for (final entry in labels.entries)
      if (value[entry.key] is String) '${entry.value} ${value[entry.key]}',
  ];
  return parts.isEmpty ? '기록의 설정 또는 파일 정보가 다릅니다' : parts.join(' · ');
}

class ImportConflictPreviewList extends StatelessWidget {
  const ImportConflictPreviewList({required this.preview, super.key});
  final ImportConflictPreview preview;
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: AppLayout.bodyPadding,
    itemCount: preview.conflicts.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return const Text(
          '다른 내용 확인 · 아직 가져오지 않았어요. 현재 기록이나 녹음 파일을 자동으로 덮어쓰지 않아요.',
        );
      }
      final conflict = preview.conflicts[index - 1], values = conflict.values;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_entity(conflict.entity)),
              Text(_reason(conflict.code)),
              for (final key in ['base', 'server', 'incoming', 'destination'])
                if (values[key] != null)
                  Text(
                    '${switch (key) {
                      'base' => '백업 기준',
                      'server' => '최신 서버',
                      'incoming' => '백업 로컬',
                      _ => '현재 기기 변경',
                    }}: ${_summary(values[key])}',
                  ),
              const Text('이번에 가져오지 않아요. 현재 기록과 백업 내용을 먼저 확인해 주세요.'),
            ],
          ),
        ),
      );
    },
  );
}
