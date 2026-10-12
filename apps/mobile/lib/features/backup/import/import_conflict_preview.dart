import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import 'import_conflicts.dart';

class ImportConflictPreviewList extends StatelessWidget {
  const ImportConflictPreviewList({required this.preview, super.key});
  final ImportConflictPreview preview;
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(AppSpacing.lg),
    itemCount: preview.conflicts.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return const Text(
          '충돌 미리보기 · 아직 적용되지 않았습니다. 같은 필드와 다른 체크섬 파일을 자동으로 덮어쓰지 않습니다.',
        );
      }
      final conflict = preview.conflicts[index - 1], values = conflict.values;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${conflict.entity} · ${conflict.fields.join(', ')}'),
              Text(conflict.code),
              for (final key in ['base', 'server', 'incoming', 'destination'])
                if (values[key] != null)
                  Text(
                    '${switch (key) {
                      'base' => '백업 기준',
                      'server' => '최신 서버',
                      'incoming' => '백업 로컬',
                      _ => '현재 기기 변경',
                    }}: ${jsonEncode(values[key])}',
                  ),
              const Text('보류됨 · 선택과 최신 상태 재검증이 필요합니다.'),
            ],
          ),
        ),
      );
    },
  );
}
