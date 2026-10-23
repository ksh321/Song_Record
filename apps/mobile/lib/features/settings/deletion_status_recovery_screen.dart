import 'package:flutter/material.dart';

import '../../core/domain/account_deletion_confirmation.dart';
import '../../core/widgets/app_icon.dart';
import '../auth/identity_link.dart';
import 'account_deletion.dart';
import 'account_deletion_screen.dart';

class _NoIdentity implements IdentityLinkProofSource {
  @override
  Future<String> linkProof(String p, String n) =>
      throw StateError('Restricted status never reauthenticates');
}

/// Protected proof recovery remains reachable without re-enabling a deleted account.
class DeletionStatusRecoveryScreen extends StatefulWidget {
  const DeletionStatusRecoveryScreen({
    required this.base,
    required this.prefix,
    this.local = false,
    this.onConfirmedDeletion,
    super.key,
  });
  final Uri base;
  final String prefix;
  final bool local;
  final Future<void> Function(AccountDeletionConfirmation)? onConfirmedDeletion;
  @override
  State<DeletionStatusRecoveryScreen> createState() =>
      _DeletionStatusRecoveryScreenState();
}

class _DeletionStatusRecoveryScreenState
    extends State<DeletionStatusRecoveryScreen> {
  List<String>? scopes;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await SecureDeletionReceiptVault.scopes(widget.prefix);
      if (mounted) {
        setState(() => scopes = value);
      }
    } catch (_) {
      if (mounted) {
        setState(() => failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('저장된 탈퇴 확인증')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '확인증은 삭제 상태 조회만 허용합니다. 로그인·계정 복구·삭제 취소 권한은 없습니다. 확인증이 없으면 재발급하거나 이메일로 조회할 수 없습니다.',
          ),
          if (failed)
            const Text('확인증 보관 목록을 읽지 못했어요. 기존 기록을 덮어쓰지 않습니다.')
          else if (scopes == null)
            const LinearProgressIndicator()
          else if (scopes!.isEmpty)
            const Text('이 서버 환경에 저장된 확인증이 없어요.')
          else
            for (var i = 0; i < scopes!.length; i++)
              ListTile(
                title: Text('탈퇴 확인증 ${i + 1}'),
                trailing: const AppIcon(Icons.chevron_right),
                onTap: () {
                  final api = AccountDeletionApi(
                    widget.base,
                    () => throw StateError('Status has no login'),
                    () => throw StateError('Status has no account commands'),
                    local: widget.local,
                  );
                  final flow = AccountDeletionFlow(
                    scopes![i],
                    api,
                    _NoIdentity(),
                    const SecureDeletionReceiptVault(),
                  );
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountDeletionScreen(
                        flow: flow,
                        statusOnly: true,
                        onAccepted: () async {
                          final owner = scopes![i].substring(
                            widget.prefix.length,
                          );
                          await widget.onConfirmedDeletion?.call(
                            flow.confirmation(owner),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    ),
  );
}
