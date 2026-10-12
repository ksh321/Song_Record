import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'export_audio_test.dart' as fixture;
import 'support/completed_capture_fixture.dart' as capture;

class Probe implements ImportAudioProbe {
  bool valid = true;
  int calls = 0;
  int duration = 12000;
  @override
  Future<Map<String, dynamic>> inspect(File file) async {
    calls++;
    return {
      'mime': valid ? 'audio/mp4a-latm' : 'video/mp4',
      'aac_profile': 2,
      'sample_rate': 48000,
      'channels': 1,
      'duration_ms': duration,
    };
  }
}

void main() {
  late Directory dir;
  late ImportZipStaging staging;
  late ExportManifest manifest;
  late Probe probe;
  late File existing;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('import-verify-');
    existing = File('${dir.path}/existing.m4a');
    await existing.writeAsString('normal original');
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
    final data = ExportData.fromBaseline(baseline);
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
          durationMs: 12000,
        ),
      ],
    );
    Future<File> file(String name) async {
      final f = File('${dir.path}/export/$name');
      await f.parent.create(recursive: true);
      return f;
    }

    await (await file(manifest.files.single.relativePath!))
        .writeAsBytes(capture.bytes);
    final zip = await ExportZipWriter(
      file: file,
      requireCurrent: () {},
    ).write(data, manifest);
    staging = await ImportZipReader(
      requireCurrent: () {},
      availableBytes: () async => 128 * 1024 * 1024,
    ).unpack(zip.file, dir);
    probe = Probe();
  });
  tearDown(() async {
    expect(await existing.readAsString(), 'normal original');
    await dir.delete(recursive: true);
  });
  ImportValidator validator({String owner = fixture.owner}) =>
      ImportValidator(owner: owner, requireCurrent: () {}, audio: probe);
  test('real exporter roundtrip validates every included file without existing writes', () async {
    final result = await validator().verify(staging);
    expect(result.wholeBackupValid, true);
    expect(probe.calls, 1);
    expect(result.data.toJson()['records'], isNotEmpty);
    expect(result.toString(), isNot(contains(fixture.owner)));
  });
  test(
    'hash corruption blocks whole import and never probes unverified audio',
    () async {
      await staging.file(manifest.files.single.relativePath!).writeAsBytes([
        9,
        2,
        3,
        4,
        5,
      ]);
      final result = await validator().verify(staging);
      expect(result.wholeBackupValid, false);
      expect(result.issues.single.code, 'AUDIO_HASH_OR_SIZE');
      expect(probe.calls, 0);
    },
  );
  test(
    'missing declared audio is a blocking error rather than skipped success',
    () async {
      await staging.file(manifest.files.single.relativePath!).delete();
      final result = await validator().verify(staging);
      expect(result.wholeBackupValid, false);
    },
  );
  test(
    'actual audio format must match allowed AAC settings and duration',
    () async {
      probe.valid = false;
      final result = await validator().verify(staging);
      expect(result.issues.single.code, 'AUDIO_FORMAT');
      expect(result.wholeBackupValid, false);
    },
  );
  for (final duration in [361000, 361001]) {
    test(
      'duration boundary $duration uses the existing 361-second contract',
      () async {
        probe.duration = duration;
        final value = manifest.toJson();
        (value['files'] as List).single['duration_ms'] = duration;
        await staging.file('manifest.json').writeAsString(jsonEncode(value));
        final result = await validator().verify(staging);
        expect(result.wholeBackupValid, duration == 361000);
      },
    );
  }
  test(
    'structured nested file must be an object rather than an accepted scalar',
    () async {
      final file = staging.file('data.json');
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      value['records'][0]['payload']['file'] = 'invalid';
      await file.writeAsString(jsonEncode(value));
      await expectLater(validator().verify(staging), throwsFormatException);
      expect(probe.calls, 0);
    },
  );
  test('wrong owner rejected before audio inspection', () async {
    await expectLater(
      validator(owner: capture.other).verify(staging),
      throwsFormatException,
    );
    expect(probe.calls, 0);
  });
  for (final mode in [
    'missing-json',
    'owner',
    'extra-root',
    'secret-field',
    'duplicate-key',
    'record-count',
    'scalar-object',
    'uuid-list',
  ]) {
    test('strict required JSON rejects $mode', () async {
      final file = staging.file('data.json');
      if (mode == 'missing-json') {
        await file.delete();
      } else {
        final map =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        switch (mode) {
          case 'owner':
            map['source_user_id'] = capture.other;
          case 'extra-root':
            map['token'] = 'not allowed';
          case 'secret-field':
            map['records'][0]['payload']['access_token'] = 'not allowed';
          case 'scalar-object':
            map['records'][0]['payload']['note'] = <String, Object?>{
              'title': 'invalid object',
            };
          case 'uuid-list':
            map['records'][0]['payload']['tag_ids'] = <int>[123];
          case 'record-count':
            map['records'] = <Object?>[];
          default:
            break;
        }
        var text = jsonEncode(map);
        if (mode == 'duplicate-key') {
          text = text.replaceFirst('{', '{"schema_version":1,');
        }
        await file.writeAsString(text);
      }
      await expectLater(
        validator().verify(staging),
        throwsA(anyOf(isA<FormatException>(), isA<FileSystemException>())),
      );
      expect(probe.calls, 0);
    });
  }
  test(
    'cancellation is propagated instead of converted to an audio error',
    () async {
      var count = 0;
      await expectLater(
        ImportValidator(
          owner: fixture.owner,
          requireCurrent: () {
            if (++count == 5) throw StateError('cancel');
          },
          audio: probe,
        ).verify(staging),
        throwsStateError,
      );
    },
  );
}
