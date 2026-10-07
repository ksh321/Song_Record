import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/features/sync/sync_screen.dart';

import 'sync_verification_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'verification') {
    throw StateError('Use the isolated verification debug flavor');
  }
  runApp(const MaterialApp(home: VerificationHome()));
}

class VerificationHome extends StatefulWidget {
  const VerificationHome({super.key});
  @override
  State<VerificationHome> createState() => _VerificationHomeState();
}

class _VerificationHomeState extends State<VerificationHome> {
  bool busy = false;
  String? message;
  Future<void> open(int? status, {bool canonical = false, bool changeOnReview = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    SyncVerificationFixture? fixture;
    try {
      final support = await getApplicationSupportDirectory();
      fixture = await SyncVerificationFixture.create(
        Directory('${support.path}/isolated-sync-checks'),
        authenticationStatus: status,
        canonical: canonical,
        changeOnReview: changeOnReview,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VerificationRun(fixture: fixture!, status: status),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => message = '검증 준비에 실패했어요. AI에게 알려 주세요.');
    } finally {
      await fixture?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('노래기록 동기화 검증')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('합성 자료만 사용하는 별도 앱입니다. 로그인·서버 통신·녹음은 하지 않습니다.'),
        if (message != null) Text(message!),
        FilledButton(
          onPressed: busy ? null : () => open(null, canonical: true),
          child: const Text('같은 곡 개인 편집 검증'),
        ),
        FilledButton(
          onPressed: busy ? null : () => open(null, canonical: true, changeOnReview: true),
          child: const Text('개인 편집 최신 값 변경 검증'),
        ),
        for (final status in <int?>[null, 401, 403])
          FilledButton(
            onPressed: busy ? null : () => open(status),
            child: Text(status == null ? '충돌 선택 검증' : '$status 복귀 검증'),
          ),
      ],
    ),
  );
}

class VerificationRun extends StatefulWidget {
  const VerificationRun({
    required this.fixture,
    required this.status,
    super.key,
  });
  final SyncVerificationFixture fixture;
  final int? status;
  @override
  State<VerificationRun> createState() => _VerificationRunState();
}

class _VerificationRunState extends State<VerificationRun>
    with WidgetsBindingObserver {
  bool started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => widget
      .fixture
      .controller
      .setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  widget.status == null ? '변경 검토에서 사용할 이름을 선택하세요.' : '시작 후 8초 안에 홈으로 나갔다가 복귀하세요. 응답 후 전송 1회·시도 [1, 0]이 정상입니다.',
                ),
                FilledButton(
                  onPressed: started
                      ? null
                      : () {
                          setState(() => started = true);
                          widget.fixture.controller.setEnabled(true);
                        },
                  child: const Text('검증 시작'),
                ),
                ListenableBuilder(
                  listenable: widget.fixture.controller,
                  builder: (context, _) {
                    final attempts = widget.fixture.controller.items
                        .map((i) => i.mutation.attemptCount)
                        .toList();
                    final text =
                        '전송 ${widget.fixture.transport.calls}회 · 남은 항목 시도 $attempts';
                    return Text(
                      text,
                      key: const ValueKey('verification-summary'),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(child: SyncScreen(controller: widget.fixture.controller)),
        ],
      ),
    ),
  );
}
