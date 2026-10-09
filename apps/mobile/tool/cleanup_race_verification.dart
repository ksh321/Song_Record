import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'cleanup_race_fixture.dart';
import 'local_preservation_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: PreservationCheckPage()));
}

class PreservationCheckPage extends StatefulWidget {
  const PreservationCheckPage({super.key});
  @override
  State<PreservationCheckPage> createState() => _State();
}

class _State extends State<PreservationCheckPage> {
  bool running = false;
  String result = '합성 시험 자료로 현재 폰의 영속 파일을 검사합니다. 개인 녹음은 사용하지 않습니다.';
  Future<void> run() async {
    setState(() {
      running = true;
      result = '검사 중';
    });
    try {
      final support = await getApplicationSupportDirectory();
      final root = await Directory('${support.path}/preservation_checks')
          .create(recursive: true);
      final isolated = await root.createTemp('run-');
      final checks = [
        ...await runPreservationChecks(isolated),
        ...await runCleanupRaceChecks(await root.createTemp('cleanup-run-')),
      ];
      if (mounted) {
        setState(
          () => result = '8개 모두 통과\n${checks.map((s) => '통과: $s').join('\n')}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => result = '검사 실패 — 이 문구를 AI에게 알려 주세요.');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P13-10 정리 경쟁 검증')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: running ? null : run,
            child: const Text('검증 시작'),
          ),
        ],
      ),
    ),
  );
}
