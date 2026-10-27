import 'package:flutter/material.dart';

import 'auth_session.dart';

/// Online credentials can expire without hiding the account's local library.
class ServerLoginCard extends StatelessWidget {
  const ServerLoginCard({required this.auth, super.key});
  final AuthController auth;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      if (!auth.serverLoginRequired) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('서버 동기화를 위한 로그인'),
              const SizedBox(height: 8),
              const Text(
                '내 곡·플리·기기에 있는 녹음은 계속 사용할 수 있어요. 인터넷 연결 후 기존 계정으로 로그인하면 동기화를 이어갑니다.',
              ),
              if (auth.message != null) Text(auth.message!),
              TextButton(
                onPressed: auth.busy || !auth.networkAvailable
                    ? null
                    : () => auth.reauthenticate('GOOGLE'),
                child: const Text('Google로 다시 로그인'),
              ),
              TextButton(
                onPressed: auth.busy || !auth.networkAvailable
                    ? null
                    : () => auth.reauthenticate('KAKAO'),
                child: const Text('카카오로 다시 로그인'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
