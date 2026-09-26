import 'package:flutter/material.dart';

import 'auth_session.dart';

class LogoutScreen extends StatefulWidget {
  const LogoutScreen({required this.auth, super.key});
  final AuthController auth;
  @override
  State<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends State<LogoutScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _export() async {
    if (_busy || widget.auth.exportRecovery == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.auth.exportRecovery!();
      if (mounted) {
        setState(
          () => _message = saved
              ? '현재 계정의 로컬 복구 파일을 저장했어요. 서버 자료와 이 기기에 없는 파일은 포함되지 않아요.'
              : '저장을 취소했어요. 로그아웃하지 않았어요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = '저장하지 못했어요. 녹음 상태와 저장 공간을 확인해 주세요. 원본은 유지돼요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 기기에서 로그아웃할까요?'),
        scrollable: true,
        content: const Text(
          '미전송 기록은 이 기기에 남아요. 별도 보관이 필요하면 먼저 로컬 복구 파일을 저장해 주세요. 같은 계정으로 다시 로그인하면 이 기기의 기록을 사용할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.auth.signOut();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = '로그아웃을 완료하지 못했어요. 녹음을 완료하고 서버 연결을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('로그아웃'),
        automaticallyImplyLeading: !_busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('이 기기의 로그인만 종료해요. 다른 기기 로그인은 유지돼요.'),
            const SizedBox(height: 16),
            const Text(
              '녹음 파일과 미전송 기록은 원래 계정에 남으며 다른 계정에서는 볼 수 없어요. 앱 삭제나 저장공간 초기화 전에는 별도로 보관해 주세요.',
            ),
            const SizedBox(height: 16),
            const Text(
              '로컬 복구 파일에는 현재 계정의 기기 내 정보와 실제 남아 있는 파일만 포함돼요. 서버 백업 및 앱에서의 ZIP 가져오기는 아직 제공하지 않아요. 미완료 녹음 파일은 재생이 보장되지 않아요.',
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy || widget.auth.exportRecovery == null
                  ? null
                  : _export,
              icon: const Icon(Icons.save_alt),
              label: const Text('로컬 복구 파일 저장'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _logout,
              child: const Text('로그아웃'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ),
      ),
    ),
  );
}
