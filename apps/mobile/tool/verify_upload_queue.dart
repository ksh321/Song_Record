import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'upload_verification_fixture.dart';

void main() {
  if (!kDebugMode) throw StateError('Debug verification only');
  runApp(const MaterialApp(home: UploadVerificationScreen()));
}

class UploadVerificationScreen extends StatefulWidget {
  const UploadVerificationScreen({super.key});
  @override
  State<UploadVerificationScreen> createState() => _UploadVerificationState();
}

class _UploadVerificationState extends State<UploadVerificationScreen> {
  bool busy = false;
  Map<String, bool>? result;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P12-05 파일 전송·원본 보존')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('합성 파일·시험 통신과 실제 휴대폰 저장소를 검사합니다. 실제 계정과 녹음은 변경하지 않습니다.'),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                    result = null;
                  });
                  try {
                    final root = await getApplicationSupportDirectory();
                    final rows = await verifyUploadQueue(
                      Directory('${root.path}/isolated-upload-checks'),
                    );
                    if (mounted) setState(() => result = rows);
                  } catch (e) {
                    if (mounted) {
                      setState(
                        () => error = '검사 실패: ${e.runtimeType}. AI에게 알려 주세요.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '검사 중' : '검증 시작'),
        ),
        if (error != null) Text(error!),
        for (final r in result?.entries ?? <MapEntry<String, bool>>[])
          ListTile(title: Text(r.key), trailing: Text(r.value ? '통과' : '실패')),
        if (result?.values.every((v) => v) == true)
          const Text('7개 항목 모두 통과. 채팅에 모두 통과라고 알려 주세요.'),
      ],
    ),
  );
}
