import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'export_data.dart';
import 'export_manifest.dart';
import 'recordings_csv.dart';

const backupPrivacyNotice =
    '개인정보·메모·녹음이 포함된 비암호화 ZIP입니다. 안전한 위치에 보관해 주세요. '
    '앱 밖의 독립 사본은 앱에서 삭제하거나 탈퇴해도 남습니다.';

typedef ExportFile = Future<File> Function(String name);

int _crc(List<int> bytes) {
  var value = 0xffffffff;
  for (final byte in bytes) {
    value ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      value = (value >> 1) ^ ((value & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return value ^ 0xffffffff;
}

Uint8List _header(int size, List<(int, int, int)> fields) {
  final buffer = ByteData(size);
  for (final (offset, width, value) in fields) {
    if (width == 2) {
      buffer.setUint16(offset, value, Endian.little);
    } else {
      buffer.setUint32(offset, value, Endian.little);
    }
  }
  return buffer.buffer.asUint8List();
}

final class ExportZip {
  ExportZip(
    this.file,
    this.size,
    this.checksum,
    this.dataHash,
    this.manifestHash,
  );
  final File file;
  final int size;
  final String checksum;
  final String dataHash, manifestHash;
}

/// Stored ZIP: bounded per-audio memory, UTF-8 names, no filesystem metadata,
/// no symlinks, paths exclusively from the validated manifest. No ZIP64 silently.
final class ExportZipWriter {
  ExportZipWriter({required this.file, required this.requireCurrent});
  final ExportFile file;
  final void Function() requireCurrent;
  bool _busy = false;

  Future<ExportZip> write(ExportData data, ExportManifest manifest) async {
    if (_busy) throw StateError('ZIP already active');
    _busy = true;
    RandomAccessFile? output;
    try {
      requireCurrent();
      final root = data.toJson();
      if (!manifest.collectionFinished ||
          root['export_id'] != manifest.exportId ||
          root['source_user_id'] != manifest.sourceUserId ||
          data.metadataCount != manifest.metadataCount) {
        throw const FormatException('Backup boundary mismatch');
      }
      final part = await file('export.zip.part');
      output = await part.open(mode: FileMode.write);
      final central = BytesBuilder(copy: false);
      var offset = 0, count = 0;
      Future<void> entry(String name, List<int> bytes) async {
        requireCurrent();
        final names = utf8.encode(name), crc = _crc(bytes);
        if (++count > 65535 || offset + bytes.length + 256 > 0xffffffff) {
          throw StateError('Backup exceeds ZIP limits');
        }
        final local = _header(30, [
          (0, 4, 0x04034b50),
          (4, 2, 20),
          (6, 2, 0x800),
          (14, 4, crc),
          (18, 4, bytes.length),
          (22, 4, bytes.length),
          (26, 2, names.length),
        ]);
        central.add(
          _header(46, [
            (0, 4, 0x02014b50),
            (4, 2, 20),
            (6, 2, 20),
            (8, 2, 0x800),
            (16, 4, crc),
            (20, 4, bytes.length),
            (24, 4, bytes.length),
            (28, 2, names.length),
            (42, 4, offset),
          ]),
        );
        central.add(names);
        await output!.writeFrom(local);
        await output!.writeFrom(names);
        await output!.writeFrom(bytes);
        offset += local.length + names.length + bytes.length;
      }

      await entry('manifest.json', utf8.encode(manifest.encode()));
      await entry('data.json', utf8.encode(data.encode()));
      await entry('recordings.csv', recordingsCsv(data, manifest));
      for (final audio in manifest.files.where((entry) => entry.included)) {
        requireCurrent();
        final source = await file(audio.relativePath!);
        if (await source.length() != audio.sizeBytes ||
            audio.sizeBytes! > 6291456) {
          throw const FormatException('Staged audio size mismatch');
        }
        final bytes = await source.readAsBytes();
        if (bytes.length != audio.sizeBytes ||
            sha256.convert(bytes).toString() != audio.sha256) {
          throw const FormatException('Staged audio checksum mismatch');
        }
        await entry(audio.relativePath!, bytes);
      }
      final directory = central.takeBytes();
      if (offset + directory.length + 22 > 0xffffffff) {
        throw StateError('Backup exceeds ZIP limits');
      }
      await output.writeFrom(directory);
      await output.writeFrom(
        _header(22, [
          (0, 4, 0x06054b50),
          (8, 2, count),
          (10, 2, count),
          (12, 4, directory.length),
          (16, 4, offset),
        ]),
      );
      await output.flush();
      await output.close();
      output = null;
      requireCurrent();
      if (await part.length() != offset + directory.length + 22) {
        throw const FormatException('Incomplete ZIP output');
      }
      // Verify a disk read, not the hash of input buffers.
      final hash = (await sha256.bind(part.openRead()).first).toString();
      requireCurrent();
      final target = await file('export.zip');
      await part.rename(target.path);
      requireCurrent();
      return ExportZip(
        target,
        await target.length(),
        hash,
        sha256.convert(utf8.encode(data.encode())).toString(),
        sha256.convert(utf8.encode(manifest.encode())).toString(),
      );
    } finally {
      await output?.close();
      _busy = false;
    }
  }
}

abstract interface class BackupDestination {
  Future<void> cancel();
  Future<bool> save(
    ExportZip zip, {
    required String owner,
    required String environment,
    required String jobId,
  });
}

final class AndroidBackupDestination implements BackupDestination {
  const AndroidBackupDestination();
  @override
  Future<void> cancel() =>
      const MethodChannel('song_record/audio_export')
          .invokeMethod<void>('cancelBackup');
  @override
  Future<bool> save(
    ExportZip zip, {
    required String owner,
    required String environment,
    required String jobId,
  }) async =>
      await const MethodChannel('song_record/audio_export')
          .invokeMethod<bool>('exportBackup', {
            'userId': owner,
            'environment': environment,
            'recordingId': jobId,
            'path': zip.file.path,
            'size': zip.size,
            'checksum': zip.checksum,
            'filename': 'song-record-backup-$jobId.zip',
          }) ??
      false;
}
