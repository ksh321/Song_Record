import 'package:flutter/material.dart';

import 'auth_session.dart';
import 'identity_link.dart';

class IdentityLinkScreen extends StatefulWidget {
  const IdentityLinkScreen({required this.flow, super.key});
  final IdentityLinkFlow flow;
  @override
  State<IdentityLinkScreen> createState() => _IdentityLinkScreenState();
}

class _IdentityLinkScreenState extends State<IdentityLinkScreen> {
  List<String>? _providers;
  bool _busy = false;
  String? _message;
  String name(String provider) => provider == 'GOOGLE' ? 'Google' : '카카오';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final providers = await widget.flow.load();
      if (mounted) setState(() => _providers = providers);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = '연결 정보를 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link(String target) async {
    final providers = _providers;
    if (_busy || providers == null || providers.isEmpty) return;
    final existing = providers.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${name(target)} 계정 연결'),
        scrollable: true,
        content: Text(
          '먼저 현재 계정의 ${name(existing)} 로그인을 다시 확인한 뒤, 연결할 ${name(target)} 계정을 선택해 주세요.\n\n다른 노래기록 계정에서 사용 중인 계정은 연결하거나 합칠 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('본인 확인 시작'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = '현재 계정을 확인한 뒤 연결할 계정을 선택해 주세요.';
    });
    var linked = false;
    try {
      await widget.flow.link(existing, target);
      linked = true;
      final providers = await widget.flow.load();
      if (mounted) {
        setState(() {
          _providers = providers;
          _message = '${name(target)} 계정을 연결했어요.';
        });
      }
    } on LoginCancelled {
      if (mounted) setState(() => _message = '계정 연결을 취소했어요.');
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _message = linked ? '연결은 완료됐어요. 새로고침해서 확인해 주세요.' : e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '연결 결과를 확인하지 못했어요. 새로고침으로 연결 상태를 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(String provider) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${name(provider)} 연결 해제'),
        scrollable: true,
        content: const Text(
          '이 로그인 수단을 해제할까요? 남아 있는 로그인 수단으로 같은 기록을 이용할 수 있어요. 현재 세션과 기록은 유지돼요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('연결 해제'),
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
      await widget.flow.unlink(provider);
      final providers = await widget.flow.load();
      if (mounted) {
        setState(() {
          _providers = providers;
          _message = '${name(provider)} 연결을 해제했어요.';
        });
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = '해제 결과를 확인하지 못했어요. 새로고침해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('로그인 계정 연결'),
        automaticallyImplyLeading: !_busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '연결된 로그인 수단으로 같은 노래기록 계정을 사용할 수 있어요. 이메일이 같아도 자동으로 연결되지 않아요.',
            ),
            const SizedBox(height: 20),
            if (_providers != null)
              for (final provider in ['GOOGLE', 'KAKAO'])
                Card(
                  child: ListTile(
                    title: Text(name(provider)),
                    subtitle: Text(
                      _providers!.contains(provider) ? '연결됨' : '연결되지 않음',
                    ),
                    trailing: _providers!.contains(provider)
                        ? (widget.flow.canUnlink
                              ? TextButton(
                                  onPressed: _busy || _providers!.length <= 1
                                      ? null
                                      : () => _unlink(provider),
                                  child: Text(
                                    _providers!.length <= 1 ? '마지막 수단' : '해제',
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  semanticLabel: '연결됨',
                                ))
                        : TextButton(
                            onPressed: _busy ? null : () => _link(provider),
                            child: const Text('연결'),
                          ),
                  ),
                ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('새로고침'),
            ),
          ],
        ),
      ),
    ),
  );
}
