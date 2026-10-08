import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import '../tool/deleted_song_verification.dart';
import '../tool/upload_verification_fixture.dart';




void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('durable account upload queue keeps originals across every transfer outcome', () async {
    final root = await Directory.systemTemp.createTemp('sr-upload-check-');
    try {
      final result = await verifyUploadQueue(root);
      expect(result.length, 7);
      for (final r in result.entries) {
        expect(r.value, isTrue, reason: r.key);
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'resolved offline recording history does not block the acknowledged file',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-upload-history-');
      try {
        final original = await verifyDeletedSong(root);
        expect(original.values.every((v) => v), isTrue);
        final run =
            (await root.list().where((f) => f is Directory).toList()).single
                as Directory;
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => run,
          temporaryDirectory: () async => run,
        );
        try {
          final store = await manager.openAccount(uploadFixtureId(1));
          await store.discoverUploads();
          expect((await store.uploadStatus()).length, 1);
          expect(await store.claimUpload(), isNotNull);
        } finally {
          await manager.logout();
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
