import 'package:flutter/material.dart';

import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/routing/app_routes.dart';

import '../auth/identity_link.dart';
import '../auth/identity_link_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.showDevelopmentTools,
    this.identityLink,
    super.key,
  });

  final bool showDevelopmentTools;
  final IdentityLinkFlow? identityLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        leading: IconButton(
          tooltip: '뒤로가기',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('나에게 맞는 노래 기록', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (identityLink != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('로그인 계정 연결'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => IdentityLinkScreen(flow: identityLink!),
                    ),
                  ),
                ),
              )
            else
              const Text('설정 기능을 준비하고 있어요.'),
            if (showDevelopmentTools) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const Text('개발 도구', style: AppTypography.supporting),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('서버 연결 확인'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed<void>(AppRoutes.health),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
