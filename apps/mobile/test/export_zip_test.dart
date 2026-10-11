import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_job.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';

import 'export_audio_test.dart' as fixture;
import 'support/completed_capture_fixture.dart' as capture;

void main() {
  late Directory directory;
  late ExportData data;
  late ExportManifest manifest;
  Future<File> file(String name) async {
    final target = File('${directory.path}/$name');
    await target.parent.create(recursive: true);
    return target;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-zip-');
    final source = fixture.baseline([fixture.recording(1)]);
    final baseline = ExportBaseline(
      id: source.id,
      owner: source.owner,
      includeTrash: false,
      manifest: null,
      createdAt: source.createdAt,
      entries: source.entries,
      local: {
        ...source.local,
        'baseline': [
          {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
        ],
      },
    );
    data = ExportData.fromBaseline(baseline);
    manifest = ExportManifest.fromBaseline(
      baseline,
      metadataCount: data.metadataCount,
      files: [
        ExportAudioEntry(
          recordingId: fixture.id(1),
          selected: true,
          included: true,
          missingReason: null,
          sha256: sha256.convert(capture.bytes).toString(),
          sizeBytes: capture.bytes.length,
          durationMs: 1000,
        ),
      ],
    );
    await (await file(manifest.files.single.relativePath!))
        .writeAsBytes(capture.bytes);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'ZIP central directory matches exact data, manifest, CSV and UUID audio',
    () async {
      final zip = await ExportZipWriter(
        file: file,
        requireCurrent: () {},
      ).write(data, manifest);
      final bytes = await zip.file.readAsBytes(),
          view = ByteData.sublistView(await zip.file.readAsBytes());
      final end = bytes.length - 22;
      expect(view.getUint32(end, Endian.little), 0x06054b50);
      expect(view.getUint16(end + 8, Endian.little), 4);
      var central = view.getUint32(end + 16, Endian.little);
      final entries = <String, List<int>>{};
      for (var index = 0; index < 4; index++) {
        expect(view.getUint32(central, Endian.little), 0x02014b50);
        expect(view.getUint16(central + 10, Endian.little), 0);
        final size = view.getUint32(central + 24, Endian.little);
        final nameLength = view.getUint16(central + 28, Endian.little);
        final local = view.getUint32(central + 42, Endian.little);
        final name = utf8.decode(
          bytes.sublist(central + 46, central + 46 + nameLength),
        );
        expect(view.getUint32(local, Endian.little), 0x04034b50);
        expect(
          view.getUint32(local + 14, Endian.little),
          view.getUint32(central + 16, Endian.little),
        );
        final start = local + 30 + view.getUint16(local + 26, Endian.little);
        entries[name] = bytes.sublist(start, start + size);
        central += 46 + nameLength;
      }
      expect(central, end);
      expect(entries.keys, [
        'manifest.json',
        'data.json',
        'recordings.csv',
        manifest.files.single.relativePath,
      ]);
      expect(utf8.decode(entries['data.json']!), data.encode());
      expect(
        ExportManifest.decode(utf8.decode(entries['manifest.json']!))
            .includedAudioCount,
        1,
      );
      expect(entries[manifest.files.single.relativePath], capture.bytes);
      expect(zip.checksum, sha256.convert(bytes).toString());
      final independentFixture =
          Platform.environment['SONG_RECORD_ZIP_FIXTURE'];
      if (independentFixture != null) await zip.file.copy(independentFixture);
    },
  );

  test(
    'bad stage or cancellation preserves previous ZIP and original stage',
    () async {
      final old = await file('export.zip');
      await old.writeAsString('previous valid artifact');
      await (await file(manifest.files.single.relativePath!)).writeAsBytes([8]);
      await expectLater(
        ExportZipWriter(
          file: file,
          requireCurrent: () {},
        ).write(data, manifest),
        throwsFormatException,
      );
      expect(await old.readAsString(), 'previous valid artifact');
      expect(
        await (await file(manifest.files.single.relativePath!)).readAsBytes(),
        [8],
      );
      await expectLater(
        ExportZipWriter(
          file: file,
          requireCurrent: () => throw StateError('cancelled'),
        ).write(data, manifest),
        throwsStateError,
      );
      expect(await old.readAsString(), 'previous valid artifact');
    },
  );

  test('private checkpoint restores frozen provenance, files and ZIP; rejects corruption and owner change', () async {
    final job = ExportJob(
      owner: fixture.owner,
      id: fixture.token,
      file: file,
      requireCurrent: () {},
    );
    await job.save(data, manifest);
    final partial = await job.resume();
    expect(partial.zip, isNull);
    expect(partial.data.encode(), data.encode());
    final zip = await ExportZipWriter(
      file: file,
      requireCurrent: () {},
    ).write(data, manifest);
    await job.save(data, manifest, zip: zip);
    final changed = ExportData.fromPrivateCheckpoint(
      data.encode().replaceFirst('ACTIVE', 'TRASHED'),
    );
    await expectLater(
      job.save(changed, manifest, zip: zip),
      throwsFormatException,
    );
    expect((await job.resume()).externallySaved, isFalse);
    await job.save(data, manifest, zip: zip, externallySaved: true);
    expect((await job.resume()).externallySaved, isTrue);
    await expectLater(
      ExportJob(
        owner: fixture.id(2),
        id: fixture.token,
        file: file,
        requireCurrent: () {},
      ).resume(),
      throwsFormatException,
    );
    await (await file('data.json')).writeAsString('{}');
    await expectLater(job.resume(), throwsFormatException);
    expect(await zip.file.exists(), isTrue);
    expect(
      await (await file(manifest.files.single.relativePath!)).readAsBytes(),
      capture.bytes,
    );
  });
}
