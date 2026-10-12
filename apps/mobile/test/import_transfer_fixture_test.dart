import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';

import '../tool/import_transfer_verification.dart' as demo;

void main() {
  test('device test fixture satisfies actual thirty-minute nineteen-entity framing', () async {
    final dir = await Directory.systemTemp.createTemp('p22-device-framing-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
    );
    try {
      final store = await manager.openAccount(demo.owner),
          transport = demo.FixtureTransport();
      final result = await ImportPreflight(
        store: store,
        transport: transport,
        session: () async => AuthSession(
          userId: demo.owner,
          deviceId: demo.id(1200),
          accessToken: 'synthetic',
          refreshToken: 'synthetic',
          accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
          refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
        requireCurrent: () {},
        clock: DateTime.now,
      ).readReady(transport.fixture['manifest']['snapshot_token'] as String);
      expect(result.owner, demo.owner);
      expect(
        result.manifest.expiresAt.difference(result.manifest.readyAt),
        const Duration(minutes: 30),
      );
      expect(result.manifest.counts.length, 19);
    } finally {
      await manager.logout();
      await dir.delete(recursive: true);
    }
  });
}
