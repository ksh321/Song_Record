import 'package:flutter/material.dart';

import '../../../core/widgets/ui_controls.dart';
import 'import_outcome.dart';

class ImportOutcomeView extends StatelessWidget {
  const ImportOutcomeView({required this.result, super.key});
  final ImportOutcome result;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: AppLayout.bodyPadding,
      children: [
        Text(result.complete ? '가져오기 확인 완료' : '가져오기 확인 · 남은 항목이 있습니다'),
        for (final entry in {
          '확인된 정보': result.information,
          '검증된 이 기기 파일': result.files,
          '누락 파일': result.missingFiles,
          '이번에 가져오지 않은 항목': result.held,
          '현재 기록과 내용이 다른 항목': result.conflicts,
          '적용 대기': result.pending,
          '서버 보관 확인이 필요한 녹음': result.uploadCandidates.length,
        }.entries)
          ListTile(title: Text(entry.key), trailing: Text('${entry.value}')),
        const Text(
          '정보 반영과 파일 복원은 별개입니다. 복원 파일 전체를 업로드하지 않으며, 업로드 후보도 서버 승인·용량·실제 업로드 결과를 확인해야 합니다.',
        ),
      ],
    ),
  );
}
