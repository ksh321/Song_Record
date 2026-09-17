import 'package:flutter/material.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/features/health/health_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/network/health_client.dart';
import 'package:song_record/routing/app_routes.dart';

class SongRecordApp extends StatelessWidget {
  const SongRecordApp({
    required this.config,
    this.healthLoader,
    this.recorderGateway = const MethodChannelRecorderGateway(),
    super.key,
  });

  final AppConfig config;
  final HealthLoader? healthLoader;
  final RecorderGateway recorderGateway;

  @override
  Widget build(BuildContext context) {
    final loadHealth =
        healthLoader ?? HealthClient(apiBaseUrl: config.apiBaseUrl).fetch;

    return MaterialApp(
      title: '노래기록',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.prod,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => HealthScreen(
          config: config,
          healthLoader: loadHealth,
          recorderGateway: recorderGateway,
        ),
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
    );
  }
}
