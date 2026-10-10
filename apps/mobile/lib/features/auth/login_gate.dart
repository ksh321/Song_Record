import 'package:flutter/material.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';

import '../sync/sync_controller.dart';
import 'auth_session.dart';
import 'identity_link.dart';

class LoginGate extends StatefulWidget {
  const LoginGate({
    required this.controller,
    required this.config,
    this.syncController,
    this.localRepository,
    super.key,
  });
  final AuthController controller;
  final AppConfig config;
  final SyncController? Function()? syncController;
  final LocalRepository? Function()? localRepository;
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.syncController?.call()?.setForeground(
      state == AppLifecycleState.resumed,
    );
    if (state == AppLifecycleState.resumed &&
        widget.controller.phase == AuthPhase.ready) {
      // Keep the existing navigation/recorder tree while silently refreshing.
      widget.controller.validSession().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final auth = widget.controller;
      if (auth.phase == AuthPhase.ready) {
        return SongRecordApp(
          key: ValueKey(auth.session!.userId),
          config: widget.config,
          authController: auth,
          syncController: widget.syncController?.call(),
          localRepository: widget.localRepository,
          identityLink:
              auth.api is IdentityLinkApi &&
                  auth.proofs is IdentityLinkProofSource
              ? IdentityLinkFlow(
                  auth,
                  auth.api as IdentityLinkApi,
                  auth.proofs as IdentityLinkProofSource,
                )
              : null,
        );
      }
      return MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.mic_none, size: 56),
                      const SizedBox(height: 16),
                      const Text(
                        '노래기록',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '로그인하고 나의 노래 기록을 이어가세요.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (auth.phase == AuthPhase.loading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        FilledButton(
                          onPressed: auth.busy
                              ? null
                              : () => auth.signIn('GOOGLE'),
                          child: const Text('Google로 계속하기'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFEE500),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: auth.busy
                              ? null
                              : () => auth.signIn('KAKAO'),
                          child: const Text('카카오로 계속하기'),
                        ),
                        if (auth.phase == AuthPhase.unavailable)
                          TextButton(
                            onPressed: auth.busy ? null : auth.restore,
                            child: const Text('다시 연결하기'),
                          ),
                        if (auth.busy)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                      if (auth.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              auth.message!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        '처음 로그인할 때는 인터넷 연결이 필요해요.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
