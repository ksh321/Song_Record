import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/trash/trash_screens.dart';
import 'package:song_record/features/trash/trash_workflow.dart';

import 'trash_verification_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  final owner = UuidValue.random().value;
  await const MethodChannel(
    'song_record/account',
  ).invokeMethod<void>('setAccount', {'userId': owner, 'environment': 'dev'});
  final manager = AccountStoreManager(environment: AppEnvironment.dev),
      store = await manager.openAccount(owner),
      fixture = TrashVerificationFixture(store);
  await fixture.initialize();
  final actions = TrashWorkflow(
    repository: fixture.repository,
    api: fixture,
    journal: SecureTrashJournal('dev', owner),
    requireCurrent: store.requireActive,
    wakeSync: () {},
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: TrashVerificationHome(fixture: fixture, actions: actions),
    ),
  );
}

class TrashVerificationHome extends StatefulWidget {
  const TrashVerificationHome({
    required this.fixture,
    required this.actions,
    super.key,
  });
  final TrashVerificationFixture fixture;
  final TrashActions actions;
  @override
  State<TrashVerificationHome> createState() => _State();
}

class _State extends State<TrashVerificationHome> {
  String? result;
  bool busy = false;
  Future<void> open(Widget screen) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) setState(() {});
  }

  Future<void> send() async {
    setState(() => busy = true);
    try {
      await widget.fixture.synchronize();
      if (mounted) {
        setState(
          () => result =
              '전송 완료 · ${widget.fixture.records.values.map((v) => v['lifecycle_state']).join(' / ')}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => result = '검사 전송 실패 · 원본 유지');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P20-10 삭제·복원 검증')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('합성 서버 · 별도 계정/DB · 개인 파일·실제 R2 작업 없음'),
          for (final n in [2010, 2011])
            FilledButton(
              onPressed: busy
                  ? null
                  : () => open(
                      DeleteScreen(
                        actions: widget.actions,
                        id: trashId(n),
                        title:
                            widget.fixture.songs[trashId(n)]!['title']
                                as String,
                      ),
                    ),
              child: Text(n == 2010 ? '곡만 삭제 검사' : '함께 삭제 검사'),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () => open(
                    DeleteScreen(
                      actions: widget.actions,
                      id: trashId(2021),
                      title: '고정 녹음 삭제 확인',
                      recording: true,
                    ),
                  ),
            child: const Text('녹음 삭제 검사'),
          ),
          FilledButton(
            onPressed: busy ? null : send,
            child: const Text('대기 삭제 전송'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => open(TrashScreen(actions: widget.actions)),
            child: const Text('휴지통 열기'),
          ),
          SwitchListTile(
            value: widget.fixture.fail,
            onChanged: busy
                ? null
                : (v) => setState(() => widget.fixture.fail = v),
            title: const Text('삭제 실패 응답'),
          ),
          SwitchListTile(
            value: widget.fixture.loseResponse,
            onChanged: busy
                ? null
                : (v) => setState(() => widget.fixture.loseResponse = v),
            title: const Text('처리 후 응답 유실'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    await widget.fixture.completePurge();
                    if (mounted) {
                      setState(
                        () => result =
                            '영구 삭제 동기화 완료 · 보존 녹음 ${widget.fixture.records[trashId(2020)]!['lifecycle_state']}',
                      );
                    }
                  },
            child: const Text('합성 서버 영구 삭제 완료 확인'),
          ),
          if (result != null) Text(result!),
          for (final row in widget.fixture.songs.values)
            Text('${row['title']}: ${row['lifecycle_state']}'),
          for (final row in widget.fixture.records.values)
            Text(
              '${row['title_snapshot']}: ${row['lifecycle_state']} / ${row['note']}',
            ),
        ],
      ),
    ),
  );
}
