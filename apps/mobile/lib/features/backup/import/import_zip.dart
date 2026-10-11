import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

const _jsonLimit = 100 * 1024 * 1024;
const _audioLimit = 6 * 1024 * 1024;
const _reserve = 16 * 1024 * 1024;

final class ImportZipFailure implements Exception {
  const ImportZipFailure(this.code);
  final String code;
  @override
  String toString() => 'ImportZipFailure[$code]';
}

void _check(bool ok, [String code = 'ZIP_CORRUPT']) {
  if (!ok) throw ImportZipFailure(code);
}

final class ImportZipEntry {
  const ImportZipEntry(
    this.name,
    this.offset,
    this.packed,
    this.size,
    this.method,
    this.flags,
    this.crc,
    this.zip64,
  );
  final String name;
  final int offset, packed, size, method, flags, crc;
  final bool zip64;
  bool get directory => name.endsWith('/');
}

final class ImportZipStaging {
  ImportZipStaging(this.directory, Map<String, ImportZipEntry> entries)
    : entries = Map.unmodifiable(entries);
  final Directory directory;
  final Map<String, ImportZipEntry> entries;
  File file(String name) {
    _check(entries.containsKey(name) && !entries[name]!.directory);
    return File(path.joinAll([directory.path, ...name.split('/')]));
  }

  @override
  String toString() => 'ImportZipStaging[REDACTED]';
}

/// Initial stored exports and standard deflate/ZIP64 archives. All output is
/// owned temporary data; no existing user DB or recording is opened for writing.
final class ImportZipReader {
  ImportZipReader({required this.requireCurrent, required this.availableBytes});
  final void Function() requireCurrent;
  final Future<int> Function() availableBytes;

  Future<ImportZipStaging> unpack(File zip, Directory stagingParent) async {
    RandomAccessFile? input;
    Directory? output;
    try {
      requireCurrent();
      input = await zip.open();
      final length = await input.length();
      Future<Uint8List> read(int offset, int count) async {
        requireCurrent();
        _check(offset >= 0 && count >= 0 && offset <= length - count);
        await input!.setPosition(offset);
        final bytes = await input!.read(count);
        _check(bytes.length == count);
        return bytes;
      }

      ByteData data(Uint8List bytes) => ByteData.sublistView(bytes);
      final tail = await read(
        length > 65557 ? length - 65557 : 0,
        length > 65557 ? 65557 : length,
      );
      final tailData = data(tail);
      int? eocd;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (tailData.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + tailData.getUint16(i + 20, Endian.little) == tail.length) {
          eocd = length - tail.length + i;
          break;
        }
      }
      _check(eocd != null);
      final end = data(await read(eocd!, 22));
      _check(
        end.getUint16(4, Endian.little) == 0 &&
            end.getUint16(6, Endian.little) == 0,
        'ZIP_UNSUPPORTED',
      );
      var count = end.getUint16(10, Endian.little);
      var directorySize = end.getUint32(12, Endian.little);
      var directoryOffset = end.getUint32(16, Endian.little);
      var directoryEnd = eocd;
      final hasLocator =
          eocd >= 20 &&
          data(await read(eocd - 20, 4)).getUint32(0, Endian.little) ==
              0x07064b50;
      if ((count == 65535 && hasLocator) ||
          directorySize == 0xffffffff ||
          directoryOffset == 0xffffffff) {
        final locator = data(await read(eocd - 20, 20));
        _check(
          locator.getUint32(0, Endian.little) == 0x07064b50 &&
              locator.getUint32(4, Endian.little) == 0 &&
              locator.getUint32(16, Endian.little) == 1,
        );
        final offset = locator.getUint64(8, Endian.little);
        final extended = data(await read(offset, 56));
        _check(
          extended.getUint32(0, Endian.little) == 0x06064b50 &&
              extended.getUint64(4, Endian.little) >= 44 &&
              offset + 12 + extended.getUint64(4, Endian.little) == eocd - 20 &&
              extended.getUint32(16, Endian.little) == 0 &&
              extended.getUint32(20, Endian.little) == 0,
        );
        count = extended.getUint64(32, Endian.little);
        _check(count == extended.getUint64(24, Endian.little));
        directorySize = extended.getUint64(40, Endian.little);
        directoryOffset = extended.getUint64(48, Endian.little);
        directoryEnd = offset;
      } else {
        _check(count == end.getUint16(8, Endian.little));
      }
      _check(count >= 0 && count <= 100000, 'ZIP_TOO_MANY_ENTRIES');
      _check(
        directorySize >= 0 &&
            directorySize <= 128 * 1024 * 1024 &&
            directoryOffset >= 0 &&
            directoryOffset + directorySize == directoryEnd,
      );
      final entries = <String, ImportZipEntry>{}, namesSeen = <String>{};
      var cursor = directoryOffset, jsonBytes = 0, csvBytes = 0, total = 0;
      for (var i = 0; i < count; i++) {
        final header = data(await read(cursor, 46));
        _check(header.getUint32(0, Endian.little) == 0x02014b50);
        final names = header.getUint16(28, Endian.little),
            extras = header.getUint16(30, Endian.little),
            comments = header.getUint16(32, Endian.little);
        _check(names > 0 && names <= 512 && extras <= 4096 && comments <= 4096);
        final variable = await read(cursor + 46, names + extras + comments);
        final name = utf8.decode(variable.sublist(0, names));
        final components = name.split('/');
        if (name.endsWith('/')) components.removeLast();
        _check(
          components.isNotEmpty &&
              components.every((s) => s.isNotEmpty && s != '.' && s != '..') &&
              !name.contains('\\') &&
              !name.contains(':') &&
              !RegExp(r'[<>"|?*]').hasMatch(name) &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) &&
              components.every(
                (s) =>
                    !s.endsWith('.') &&
                    !s.endsWith(' ') &&
                    !RegExp(
                      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                      caseSensitive: false,
                    ).hasMatch(s),
              ),
          'ZIP_UNSAFE_PATH',
        );
        // Windows is case insensitive, so aliases must not pass as distinct paths.
        _check(namesSeen.add(name.toLowerCase()), 'ZIP_DUPLICATE_PATH');
        final mode = header.getUint32(38, Endian.little) >> 16;
        _check(
          (mode & 0xf000) == 0 ||
              (mode & 0xf000) == 0x8000 ||
              ((mode & 0xf000) == 0x4000 && name.endsWith('/')),
          'ZIP_UNSAFE_PATH',
        );
        final flags = header.getUint16(8, Endian.little),
            method = header.getUint16(10, Endian.little);
        _check(
          (flags & ~0x80e) == 0 &&
              (method == 0 || method == 8) &&
              (method != 0 || (flags & 6) == 0),
          'ZIP_UNSUPPORTED',
        );
        var size = header.getUint32(24, Endian.little),
            packed = header.getUint32(20, Endian.little),
            offset = header.getUint32(42, Endian.little),
            disk = header.getUint16(34, Endian.little);
        final zip64 = size == 0xffffffff || packed == 0xffffffff;
        var extraOffset = names;
        while (extraOffset < names + extras) {
          _check(extraOffset + 4 <= names + extras);
          final extraData = data(variable),
              type = extraData.getUint16(extraOffset, Endian.little),
              extraSize = extraData.getUint16(extraOffset + 2, Endian.little);
          final start = extraOffset + 4, stop = start + extraSize;
          _check(stop <= names + extras);
          if (type == 1) {
            var position = start;
            int number(int width) {
              _check(position + width <= stop);
              final n = width == 8
                  ? extraData.getUint64(position, Endian.little)
                  : extraData.getUint32(position, Endian.little);
              position += width;
              return n;
            }

            if (size == 0xffffffff) size = number(8);
            if (packed == 0xffffffff) packed = number(8);
            if (offset == 0xffffffff) offset = number(8);
            if (disk == 65535) disk = number(4);
          }
          extraOffset = stop;
        }
        _check(
          disk == 0 &&
              size >= 0 &&
              packed >= 0 &&
              size != 0xffffffff &&
              packed != 0xffffffff &&
              offset != 0xffffffff,
        );
        _check(size <= 100 * packed || size == 0, 'ZIP_COMPRESSION_RATIO');
        _check(method != 0 || size == packed);
        if (name.endsWith('/')) {
          _check(size == 0);
        } else if (name.endsWith('.json')) {
          jsonBytes += size;
          _check(jsonBytes <= _jsonLimit, 'ZIP_JSON_LIMIT');
        } else if (name.endsWith('.m4a')) {
          _check(size <= _audioLimit, 'ZIP_AUDIO_LIMIT');
        } else if (name.endsWith('.csv')) {
          csvBytes += size;
          _check(csvBytes <= _jsonLimit, 'ZIP_CSV_LIMIT');
        } else {
          throw const ImportZipFailure('ZIP_UNSUPPORTED_FILE');
        }
        total += size;
        _check(
          total >= 0 && total <= 100000 * _audioLimit + 2 * _jsonLimit,
          'ZIP_LIMIT_EXCEEDED',
        );
        entries[name] = ImportZipEntry(
          name,
          offset,
          packed,
          size,
          method,
          flags,
          header.getUint32(16, Endian.little),
          zip64,
        );
        cursor += 46 + names + extras + comments;
        _check(cursor <= directoryEnd);
      }
      _check(cursor == directoryEnd);
      final aliases = entries.keys.map((n) => n.toLowerCase()).toSet();
      for (final name in entries.keys) {
        final segments = name.split('/');
        for (var i = 1; i < segments.length; i++) {
          _check(
            !aliases.contains(segments.take(i).join('/').toLowerCase()),
            'ZIP_DUPLICATE_PATH',
          );
        }
      }
      _check(await availableBytes() >= total + _reserve, 'INSUFFICIENT_SPACE');
      requireCurrent();
      output = await stagingParent.createTemp('import-');
      _check(
        path.isWithin(
          await stagingParent.resolveSymbolicLinks(),
          await output.resolveSymbolicLinks(),
        ),
        'ZIP_UNSAFE_PATH',
      );
      var previousEnd = 0, written = 0;
      final sorted = entries.values.toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));
      for (final entry in sorted) {
        _check(entry.offset >= previousEnd && entry.offset < directoryOffset);
        final local = data(await read(entry.offset, 30));
        _check(
          local.getUint32(0, Endian.little) == 0x04034b50 &&
              local.getUint16(6, Endian.little) == entry.flags &&
              local.getUint16(8, Endian.little) == entry.method,
        );
        final nameLength = local.getUint16(26, Endian.little),
            extraLength = local.getUint16(28, Endian.little);
        _check(nameLength <= 512 && extraLength <= 4096);
        _check(
          utf8.decode(await read(entry.offset + 30, nameLength)) == entry.name,
        );
        final start = entry.offset + 30 + nameLength + extraLength,
            end = start + entry.packed;
        _check(end <= directoryOffset && start >= 0);
        previousEnd = end;
        var localPacked = local.getUint32(18, Endian.little),
            localSize = local.getUint32(22, Endian.little);
        final localZip64 = localPacked == 0xffffffff || localSize == 0xffffffff;
        if (localZip64) {
          final extra = data(
            await read(entry.offset + 30 + nameLength, extraLength),
          );
          var position = 0, found = false;
          while (position < extraLength) {
            _check(position + 4 <= extraLength);
            final type = extra.getUint16(position, Endian.little),
                size = extra.getUint16(position + 2, Endian.little);
            _check(position + 4 + size <= extraLength);
            if (type == 1) {
              var q = position + 4;
              if (localSize == 0xffffffff) {
                _check(q + 8 <= position + 4 + size);
                localSize = extra.getUint64(q, Endian.little);
                q += 8;
              }
              if (localPacked == 0xffffffff) {
                _check(q + 8 <= position + 4 + size);
                localPacked = extra.getUint64(q, Endian.little);
              }
              found = true;
              break;
            }
            position += 4 + size;
          }
          _check(found);
        }
        if ((entry.flags & 8) == 0) {
          _check(
            local.getUint32(14, Endian.little) == entry.crc &&
                localPacked == entry.packed &&
                localSize == entry.size,
          );
        } else {
          _check(
            (local.getUint32(14, Endian.little) == 0 ||
                    local.getUint32(14, Endian.little) == entry.crc) &&
                (localPacked == 0 || localPacked == entry.packed) &&
                (localSize == 0 || localSize == entry.size),
          );
          var descriptor = end;
          if (data(await read(descriptor, 4)).getUint32(0, Endian.little) ==
              0x08074b50) {
            descriptor += 4;
          }
          final desc = data(
            await read(descriptor, (entry.zip64 || localZip64) ? 20 : 12),
          );
          _check(
            desc.getUint32(0, Endian.little) == entry.crc &&
                ((entry.zip64 || localZip64)
                        ? desc.getUint64(4, Endian.little)
                        : desc.getUint32(4, Endian.little)) ==
                    entry.packed &&
                ((entry.zip64 || localZip64)
                        ? desc.getUint64(12, Endian.little)
                        : desc.getUint32(8, Endian.little)) ==
                    entry.size,
          );
          previousEnd = descriptor + ((entry.zip64 || localZip64) ? 20 : 12);
          _check(previousEnd <= directoryOffset);
        }
        final destination = path.joinAll([
          output.path,
          ...entry.name.split('/'),
        ]);
        _check(path.isWithin(output.path, destination), 'ZIP_UNSAFE_PATH');
        if (entry.directory) {
          await Directory(destination).create(recursive: true);
          continue;
        }
        await File(destination).parent.create(recursive: true);
        final sink = await File(destination).open(mode: FileMode.write);
        var actual = 0, crc = 0xffffffff;
        try {
          Stream<List<int>> chunks() async* {
            var position = start;
            while (position < end) {
              final n = end - position > 8192 ? 8192 : end - position;
              yield await read(position, n);
              position += n;
            }
          }

          final Stream<List<int>> stream = entry.method == 0
              ? chunks()
              : chunks().transform(ZLibDecoder(raw: true));
          await for (final bytes in stream) {
            requireCurrent();
            actual += bytes.length;
            _check(
              actual <= entry.size &&
                  actual <=
                      (entry.name.endsWith('.m4a') ? _audioLimit : _jsonLimit),
              'ZIP_ACTUAL_SIZE_LIMIT',
            );
            written += bytes.length;
            _check(written <= total, 'ZIP_ACTUAL_SIZE_LIMIT');
            for (final byte in bytes) {
              crc = (crc >> 8) ^ _crcTable[(crc ^ byte) & 255];
            }
            await sink.writeFrom(bytes);
          }
          _check(actual == entry.size && (crc ^ 0xffffffff) == entry.crc);
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      _check(await input.length() == length);
      requireCurrent();
      return ImportZipStaging(output, entries);
    } catch (_) {
      if (output != null &&
          await output.exists() &&
          path.isWithin(
            await stagingParent.resolveSymbolicLinks(),
            await output.resolveSymbolicLinks(),
          )) {
        await output.delete(recursive: true);
      }
      rethrow;
    } finally {
      await input?.close();
    }
  }
}

final _crcTable = List<int>.generate(256, (i) {
  var n = i;
  for (var bit = 0; bit < 8; bit++) {
    n = (n >> 1) ^ ((n & 1) != 0 ? 0xedb88320 : 0);
  }
  return n;
});
