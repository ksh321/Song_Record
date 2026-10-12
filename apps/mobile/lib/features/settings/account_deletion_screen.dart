import 'package:flutter/material.dart';

import 'account_deletion.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    required this.flow,
    required this.onAccepted,
    this.statusOnly = false,
    super.key,
  });
  final AccountDeletionFlow flow;
  final Future<void> Function() onAccepted;
  final bool statusOnly;
  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool working = true, confirmed = false;
  String provider = 'GOOGLE', message = '확인증을 읽고 있어요.';
  String? status;
  bool expired = false;
  @override
  void initState() {
    super.initState();
    run(() async {
      await widget.flow.restore();
      if (widget.flow.receipt != null) {
        await check();
      } else {
        message = '현재 계정의 로그인 방식으로 최근 재인증을 진행해 주세요.';
      }
    });
  }

  Future<void> check() async {
    Map<String, dynamic> r;
    try {
      r = await widget.flow.status();
    } on DeletionFailure catch (error) {
      if (error.status != 410) rethrow;
      expired = true;
      message = '확인증이 만료됐어요. 이미 접수된 계정은 복구·재발급할 수 없습니다. 접수 전 준비만 만료됐다면 현재 활성 계정으로 새 재인증을 진행해 주세요.';
      return;
    }
    status = r['status'] as String;
    if (status != 'PREPARED') {
      await widget.onAccepted();
    }
    message = switch (status) {
      'PREPARED' => '아직 접수 전이에요. 삭제 범위를 확인하고 최종 동의해 주세요.',
      'COMPLETED' => '서비스 데이터와 운영 백업 정리가 확인됐어요.',
      'BACKUP_CLEANUP' => '서비스 데이터 삭제가 확인됐고 운영 백업을 정리하고 있어요.',
      _ => '탈퇴가 접수됐어요. 일반 이용은 차단됐고 삭제 작업이 진행됩니다.',
    };
  }

  Future<void> run(Future<void> Function() task) async {
    if (mounted) {
      setState(() => working = true);
    }
    try {
      await task();
    } catch (_) {
      message = status != null && status != 'PREPARED'
          ? '서버의 탈퇴 접수 상태는 확인됐어요. 이 기기 계정 정리를 확인하지 못했으니 확인증으로 상태를 다시 확인해 주세요.'
          : '처리를 확인하지 못했어요. 저장된 확인증으로 상태를 다시 확인해 주세요. 재인증·확인증 저장 실패 시 탈퇴를 접수하지 않습니다.';
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('계정 탈퇴')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '모든 내 곡·녹음·메모·태그·플레이리스트·서비스 보관 음원을 삭제합니다. 접수 후 로그인·새 음원 URL·업로드를 이용할 수 없습니다.',
          ),
          const SizedBox(height: 16),
          const Text(
            '운영 백업에는 최대 7일 남을 수 있어요. 오프라인 기기에는 재접속 때 반영합니다. 앱 밖에 내보낸 ZIP·M4A 사본은 회수할 수 없습니다. 기존 음원 URL은 만료 또는 객체 삭제 전까지 남을 수 있어요.',
          ),
          const SizedBox(height: 16),
          Text(message),
          if (working) const LinearProgressIndicator(),
          if (!widget.statusOnly &&
              widget.flow.loaded &&
              (widget.flow.receipt == null || expired)) ...[
            DropdownButton<String>(
              value: provider,
              items: const [
                DropdownMenuItem(value: 'GOOGLE', child: Text('Google')),
                DropdownMenuItem(value: 'KAKAO', child: Text('카카오')),
              ],
              onChanged: working ? null : (v) => setState(() => provider = v!),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () => run(() async {
                      await widget.flow.prepare(provider);
                      status = 'PREPARED';
                      expired = false;
                      message = '확인증 암호화 저장을 확인했어요. 분실 시 재발급할 수 없습니다. 아래 범위에 최종 동의하면 접수합니다.';
                    }),
              child: const Text('최근 재인증 및 확인증 준비'),
            ),
          ],
          if (!widget.statusOnly &&
              !expired &&
              widget.flow.receipt != null &&
              (status == null || status == 'PREPARED')) ...[
            CheckboxListTile(
              value: confirmed,
              onChanged: working
                  ? null
                  : (v) => setState(() => confirmed = v ?? false),
              title: const Text('위의 전체 계정 데이터 삭제 범위를 확인했고, 탈퇴에 최종 동의합니다.'),
            ),
            FilledButton(
              onPressed: working || !confirmed
                  ? null
                  : () => run(() async {
                      await widget.flow.accept(confirmed: confirmed);
                      await check();
                    }),
              child: const Text('전체 계정 삭제 접수'),
            ),
          ],
          if (widget.flow.receipt != null)
            OutlinedButton(
              onPressed: working ? null : () => run(check),
              child: const Text('확인증으로 접수 상태 확인'),
            ),
        ],
      ),
    ),
  );
}
