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
  refreshSnapshotHash(fixture);
  return fixture;
}

/// Replace synthetic entity rows while retaining the real manifest framing.
/// Relation rows use their recording UUID rather than an invented row UUID.
void replaceBusinessSnapshotRows(
  Map<String, dynamic> fixture,
  String entity,
  List<Map<String, dynamic>> values,
) {
  final page = (fixture['pages'] as List).singleWhere(
    (dynamic page) => page['entity'] == entity,
  ) as Map;
  page['entries'] = [
    for (var index = 0; index < values.length; index++)
      {
        'ordinal': index + 1,
        'resource_id': values[index]['recording_id'] ?? values[index]['id'],
        'payload': values[index],
        'canonical_payload': canonicalJson(values[index]),
      },
  ];
  (fixture['manifest']['entity_counts'] as Map)[entity] = values.length;
  refreshSnapshotHash(fixture);
}

/// Recompute the real framed manifest hash after changing synthetic rows/cursor.
void refreshSnapshotHash(Map<String, dynamic> fixture) {
  final manifest = fixture['manifest'] as Map<String, dynamic>;
  final pages = fixture['pages'] as List<dynamic>;
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
}
