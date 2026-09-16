import 'package:flutter/material.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/routing/app_routes.dart';

class SongRecordApp extends StatelessWidget {
  const SongRecordApp({
    required this.config,
    super.key,
  });

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '노래기록',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.prod,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (context) => const _HomeScreen(),
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Text('노래 기록'),
        ),
      ),
    );
  }
}
