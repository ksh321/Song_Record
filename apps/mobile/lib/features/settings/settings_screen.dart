import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/routing/app_routes.dart';

import '../../core/theme/app_appearance.dart';
import '../../core/widgets/feature_icon.dart';
import '../auth/auth_session.dart';
import '../auth/identity_link.dart';
import '../auth/identity_link_screen.dart';
import '../auth/logout_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.showDevelopmentTools,
    this.identityLink,
    this.authController,
    this.syncController,
    this.trashBuilder,
    this.backupBuilder,
    this.importBuilder,
    this.storageBuilder,
    this.classificationBuilder,
    this.deletionBuilder,
    super.key,
  });

  final WidgetBuilder? trashBuilder;
  final WidgetBuilder? backupBuilder;
  final WidgetBuilder? importBuilder, storageBuilder, classificationBuilder;
  final WidgetBuilder? deletionBuilder;
  final bool showDevelopmentTools;
  final IdentityLinkFlow? identityLink;
  final AuthController? authController;
  final SyncController? syncController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: const [ThemeToggle()],
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
            const Card(
              child: ListTile(
                leading: FeatureIcon(Icons.people_outline),
                title: Text('나의 노래기록'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (label, icon, builder) in [
              ('보관량과 고정', Icons.storage_outlined, storageBuilder),
              ('개인화와 분류 관리', Icons.palette_outlined, classificationBuilder),
              ('백업 가져오기', Icons.unarchive_outlined, importBuilder),
            ])
              Card(
                child: ListTile(
                  leading: FeatureIcon(icon),
                  title: Text(label),
                  subtitle: builder == null
                      ? const Text('현재 연결 정보를 확인할 수 없습니다.')
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: builder == null
                      ? null
                      : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(builder: builder),
                        ),
                ),
              ),
            if (backupBuilder != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.archive_outlined),
                  title: const Text('백업 내보내기'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: backupBuilder!),
                  ),
                ),
              ),
            if (trashBuilder != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.delete_outline),
                  title: const Text('휴지통'),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: trashBuilder!),
                  ),
                ),
              ),
            if (syncController != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.sync),
                  title: const Text('동기화 상태'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SyncScreen(controller: syncController!),
                    ),
                  ),
                ),
              ),
            if (identityLink != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.link),
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
            if (authController != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.logout),
                  title: const Text('로그아웃'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => LogoutScreen(auth: authController!),
                    ),
                  ),
                ),
              ),
            if (deletionBuilder != null)
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.person_remove_outlined),
                  title: const Text('계정 탈퇴'),
                  onTap: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: deletionBuilder!)),
                ),
              ),
            if (showDevelopmentTools) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const Text('개발 도구', style: AppTypography.supporting),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  leading: const FeatureIcon(Icons.monitor_heart_outlined),
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
