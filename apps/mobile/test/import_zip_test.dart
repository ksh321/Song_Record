import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

void main() {
  late Directory dir;
  File fixture(String name) => File('test/fixtures/import_zip/$name');
  ImportZipReader reader({int bytes = 128 * 1024 * 1024}) =>
      ImportZipReader(requireCurrent: () {}, availableBytes: () async => bytes);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('songrecord-safe-zip-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  for (final name in ['stored.zip', 'deflated.zip', 'local-zip64.zip']) {
    test('bounded safe extraction: $name', () async {
      final result = await reader().unpack(fixture(name), dir);
      expect(await result.file('data.json').readAsString(), '{}');
      expect(result.entries.keys, contains('data.json'));
    });
  }
  for (final item in <(String, String)>[
    ('parent.zip', 'ZIP_UNSAFE_PATH'),
    ('absolute.zip', 'ZIP_UNSAFE_PATH'),
    ('drive.zip', 'ZIP_UNSAFE_PATH'),
    ('backslash.zip', 'ZIP_UNSAFE_PATH'),
    ('reserved.zip', 'ZIP_UNSAFE_PATH'),
    ('symlink.zip', 'ZIP_UNSAFE_PATH'),
    ('duplicate.zip', 'ZIP_DUPLICATE_PATH'),
    ('prefix.zip', 'ZIP_DUPLICATE_PATH'),
    ('ratio.zip', 'ZIP_COMPRESSION_RATIO'),
    ('actual-overflow.zip', 'ZIP_ACTUAL_SIZE_LIMIT'),
    ('json-limit.zip', 'ZIP_JSON_LIMIT'),
    ('audio-limit.zip', 'ZIP_AUDIO_LIMIT'),
    ('count-limit.zip', 'ZIP_TOO_MANY_ENTRIES'),
  ]) {
    test('reject $item and preserve existing files', () async {
      final sentinel = File('${dir.path}/normal.m4a');
      await sentinel.writeAsString('existing original');
      final before = await fixture(item.$1).readAsBytes();
      await expectLater(
        reader().unpack(fixture(item.$1), dir),
        throwsA(isA<ImportZipFailure>().having((e) => e.code, 'code', item.$2)),
      );
      expect(await sentinel.readAsString(), 'existing original');
      expect(await fixture(item.$1).readAsBytes(), before);
      expect(await dir.list().length, 1);
    });
  }
  test('disk reserve checked before extraction and owned staging removed on cancellation', () async {
    await expectLater(
      reader(bytes: 1).unpack(fixture('stored.zip'), dir),
      throwsA(
        isA<ImportZipFailure>().having(
          (e) => e.code,
          'code',
          'INSUFFICIENT_SPACE',
        ),
      ),
    );
    expect(await dir.list().length, 0);
    var calls = 0;
    final cancelled = ImportZipReader(
      requireCurrent: () {
        if (++calls == 16) throw StateError('cancelled');
      },
      availableBytes: () async => 128 * 1024 * 1024,
    );
    await expectLater(
      cancelled.unpack(fixture('stored.zip'), dir),
      throwsStateError,
    );
    expect(await dir.list().length, 0);
  });
}
