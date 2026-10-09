import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/cleanup_race_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new device, lost confirmation, reopen, expiry and generation preserve last bytes', () async {
    final root = await Directory.systemTemp.createTemp('cleanup-races-');
    try {
      expect(await runCleanupRaceChecks(root), hasLength(2));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
