import 'package:flutter/material.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/health/health_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/network/health_client.dart';
import 'package:song_record/routing/app_routes.dart';

class SongRecordApp extends StatelessWidget {
  const SongRecordApp({
    required this.config,
    this.healthLoader,
    this.identityLink,
    this.recorderGateway = const MethodChannelRecorderGateway(),
    this.accent = AppAccent.initial,
    super.key,
  });

  final AppConfig config;
  final IdentityLinkFlow? identityLink;
  final HealthLoader? healthLoader;
  final RecorderGateway recorderGateway;
  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final loadHealth =
        healthLoader ?? HealthClient(apiBaseUrl: config.apiBaseUrl).fetch;

    return MaterialApp(
      title: '노래기록',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.prod,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => AppShell(recorderGateway: recorderGateway),
        AppRoutes.settings: (context) => SettingsScreen(
          showDevelopmentTools: config.environment == AppEnvironment.dev,
          identityLink: identityLink,
        ),
        if (config.environment == AppEnvironment.dev)
          AppRoutes.health: (context) =>
              HealthScreen(config: config, healthLoader: loadHealth),
      },
      theme: AppTheme.dark(accent: accent),
    );
  }
}
