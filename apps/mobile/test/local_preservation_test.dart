import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'persistent files, stale reports, content mismatch and account switch',
    () async {
      final root = await Directory.systemTemp.createTemp('song-preservation-');
      try {
        expect(await runPreservationChecks(root), hasLength(6));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
