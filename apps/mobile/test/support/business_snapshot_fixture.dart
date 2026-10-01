import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';

import '../change_payload_validation_test.dart' show songChange;

/// The shared fixture exercises numeric hash canonicalization, not domain rows.
/// Keep it unchanged and construct a complete business fixture for apply tests.
Map<String, dynamic> businessSnapshotFixture() {
  final fixture = jsonDecode(
    File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final manifest = fixture['manifest'] as Map<String, dynamic>;
  final pages = fixture['pages'] as List<dynamic>;
  final row =
      (pages.firstWhere((dynamic p) => p['entity'] == 'SONG')['entries']
                  as List<dynamic>)
              .single
          as Map<String, dynamic>;
  final payload = <String, dynamic>{
    ...songChange(row['resource_id'] as String, 1),
    'user_id': (row['payload'] as Map)['user_id'],
    'note': '한글 🎵',
  };
  row['payload'] = payload;
  row['canonical_payload'] = canonicalJson(payload);
  final bytes = BytesBuilder();
  void number(int value, int length) {
    final buffer = ByteData(length);
    if (length == 8) {
      buffer.setInt64(0, value);
    } else {
      buffer.setInt32(0, value);
    }
    bytes.add(buffer.buffer.asUint8List());
  }

  bytes.add(ascii.encode('SongRecord:snapshot-manifest:1'));
  number(manifest['snapshot_cursor'] as int, 8);
  for (final page in pages) {
    for (final entry in page['entries'] as List<dynamic>) {
      final name = ascii.encode(page['entity'] as String);
      final raw = utf8.encode(entry['canonical_payload'] as String);
      number(name.length, 4);
      bytes.add(name);
      number(entry['ordinal'] as int, 8);
      bytes.add(UuidValue(entry['resource_id'] as String).bytes);
      number(raw.length, 4);
      bytes.add(raw);
    }
  }
  manifest['manifest_hash'] = sha256.convert(bytes.takeBytes()).toString();
  return fixture;
}
