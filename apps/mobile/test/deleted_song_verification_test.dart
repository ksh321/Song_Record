import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/deleted_song_verification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'received deletion blocks stale edit but saves new recording across reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-p10-09-');
      try {
        final results = await verifyDeletedSong(root);
        expect(results.length, 6);
        for (final result in results.entries) {
          expect(result.value, isTrue, reason: result.key);
        }
      } finally {
        expect(
          root.path.split(Platform.pathSeparator).last,
          startsWith('sr-p10-09-'),
        );
        await root.delete(recursive: true);
      }
    },
  );
}
