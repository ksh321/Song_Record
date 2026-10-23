import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';
import 'package:song_record/routing/app_routes.dart';

import '../../core/theme/app_appearance.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/ui_controls.dart';
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
    void open(WidgetBuilder builder) =>
        Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
    Widget row(
      String title,
      IconData icon,
      WidgetBuilder? builder, {
      String? subtitle,
    }) => AppFeatureRow(
      title: title,
      icon: icon,
      subtitle: subtitle,
      onTap: builder == null ? null : () => open(builder),
    );
    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        AppPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: appPageBar(
        context,
        showSettings: false,
        title: const Text('설정'),
        actions: const [ThemeToggle()],
        leading: IconButton(
          tooltip: '뒤로가기',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const AppIcon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: AppLayout.bodyPadding,
          children: [
            const AppPanel(
              child: Row(
                children: [
                  FeatureIcon(Icons.people_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '나의 노래기록',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            section('내 기록 관리', [
              row('보관량과 고정', Icons.storage_outlined, storageBuilder),
              if (backupBuilder != null)
                row(
                  '백업 내보내기',
                  Icons.archive_outlined,
                  backupBuilder,
                  subtitle: '내 기록을 파일로 보관',
                ),
              row(
                '백업 가져오기',
                Icons.unarchive_outlined,
                importBuilder,
                subtitle: importBuilder == null
                    ? '현재 연결 정보를 확인할 수 없습니다.'
                    : '백업 파일에서 복원',
              ),
              if (trashBuilder != null)
                row(
                  '휴지통',
                  Icons.delete_outline,
                  trashBuilder,
                  subtitle: '삭제한 기록 복원',
                ),
            ]),
            section('앱 설정', [
              row(
                '개인화와 분류',
                Icons.palette_outlined,
                classificationBuilder,
                subtitle: '강조색 · 컨디션 · 태그',
              ),
              if (syncController != null)
                row(
                  '동기화 상태',
                  Icons.sync,
                  (_) => SyncScreen(controller: syncController!),
                ),
            ]),
            if (identityLink != null ||
                authController != null ||
                deletionBuilder != null)
              section('계정', [
                if (identityLink != null)
                  row(
                    '로그인 계정 연결',
                    Icons.link,
                    (_) => IdentityLinkScreen(flow: identityLink!),
                    subtitle: 'Google · 카카오',
                  ),
                if (authController != null)
                  row(
                    '로그아웃',
                    Icons.logout,
                    (_) => LogoutScreen(auth: authController!),
                  ),
                if (deletionBuilder != null)
                  row('계정 탈퇴', Icons.person_remove_outlined, deletionBuilder),
              ]),
            if (identityLink == null) const Text('설정 기능을 준비하고 있어요.'),
            if (showDevelopmentTools) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const Text('개발 도구', style: AppTypography.supporting),
              ListTile(
                leading: const FeatureIcon(Icons.monitor_heart_outlined),
                title: const Text('서버 연결 확인'),
                trailing: const AppIcon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed<void>(AppRoutes.health),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
