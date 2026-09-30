import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/snapshot_response.dart';

void main() {
  late Map<String, dynamic> fixture;
  late SnapshotManifest manifest;
  final now = DateTime.utc(2026, 9, 30);
  const token = '22222222-2222-4222-8222-222222222222';
  setUp(() {
    fixture = jsonDecode(
      File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    manifest = SnapshotManifest.decode(
      jsonEncode(fixture['manifest']),
      expectedToken: token,
      now: now,
    );
  });
  SnapshotPage page(
    Map<String, dynamic> data, {
    int after = 0,
    DateTime? time,
  }) => SnapshotPage.decode(
    jsonEncode(data),
    manifest: manifest,
    entity: data['entity'] as String,
    owner: fixture['owner'] as String,
    afterOrdinal: after,
    now: time ?? now,
  );
  Map<String, dynamic> songPage() => (fixture['pages'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((p) => p['entity'] == 'SONG');

  test('shared MySQL fixture verifies all 19 entities and exact UTF-8/numeric bytes', () {
    final verifier = SnapshotIntegrity(manifest);
    for (final data in fixture['pages'] as List) {
      for (final entry in page(data as Map<String, dynamic>).entries) {
        verifier.add(entry);
      }
    }
    verifier.finish(now: now);
    final entry = page(songPage()).entries.single;
    expect(entry.canonicalPayload, contains('1E+2'));
    expect(entry.payload['note'], '한글 🎵');
    entry.payload['note'] = 'attempted mutation';
    expect(entry.payload['note'], '한글 🎵');
    expect(() => manifest.counts['SONG'] = 9, throwsUnsupportedError);
    expect(entry.toString(), 'SnapshotEntry[REDACTED]');
  });
  test('manifest rejects wrong token, incomplete entities, TTL extension and expiry', () {
    final original = fixture['manifest'] as Map<String, dynamic>;
    for (final data in [
      {...original, 'snapshot_token': fixture['owner']},
      {...original, 'schema_version': 2},
      {...original, 'snapshot_cursor': -1},
      {
        ...original,
        'entity_counts': {'SONG': 1},
      },
      {...original, 'expires_at': '2026-09-30T00:31:00Z'},
      {...original, 'captured_at': '2026-02-31T00:00:00Z'},
      {...original, 'manifest_hash': 'bad'},
    ]) {
      expect(
        () => SnapshotManifest.decode(
          jsonEncode(data),
          expectedToken: token,
          now: now,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => SnapshotManifest.decode(
        jsonEncode(original),
        expectedToken: token,
        now: now.add(const Duration(minutes: 30)),
      ),
      throwsFormatException,
    );
  });
  test('page rejects mixed snapshot, baseline, expiry, extra fields and cursor family', () {
    final original = songPage();
    for (final data in [
      {...original, 'snapshot_token': fixture['owner']},
      {...original, 'snapshot_cursor': 8},
      {...original, 'expires_at': '2026-09-30T00:29:00Z'},
      {...original, 'unexpected': true},
      {...original, 'next_cursor': 'p1.other'},
      {...original, 'next_cursor': 'sp1.extra'},
      {...original, 'entries': <Object?>[]},
    ]) {
      expect(() => page(data), throwsFormatException);
    }
    expect(
      () => page(original, time: manifest.expiresAt),
      throwsFormatException,
    );
  });
  test('entry rejects wrong owner/resource, ordinal gaps and mismatched JSON representations', () {
    final original = songPage();
    final row = (original['entries'] as List).single as Map<String, dynamic>;
    for (final changed in [
      {...row, 'ordinal': 2},
      {...row, 'resource_id': fixture['owner']},
      {...row, 'canonical_payload': '{}'},
      {
        ...row,
        'payload': {
          ...row['payload'] as Map<String, dynamic>,
          'note': 'changed',
        },
      },
      {...row, 'extra': true},
    ]) {
      expect(
        () => page({
          ...original,
          'entries': [changed],
        }),
        throwsFormatException,
      );
    }
    expect(
      () => SnapshotPage.decode(
        jsonEncode(original),
        manifest: manifest,
        entity: 'SONG',
        owner: token,
        afterOrdinal: 0,
        now: now,
      ),
      throwsFormatException,
    );
  });
  test(
    'complete page checks do not replace final hash and count verification',
    () {
      final verifier = SnapshotIntegrity(manifest);
      verifier.add(page(songPage()).entries.single);
      expect(() => verifier.finish(now: now), throwsFormatException);
      final tampered = songPage();
      final row = (tampered['entries'] as List).single as Map<String, dynamic>;
      row['canonical_payload'] = (row['canonical_payload'] as String)
          .replaceFirst('한글', '다름');
      (row['payload'] as Map<String, dynamic>)['note'] = '다름 🎵';
      final altered = SnapshotIntegrity(manifest);
      for (final data in fixture['pages'] as List) {
        for (final entry in page(data as Map<String, dynamic>).entries) {
          altered.add(entry);
        }
      }
      expect(() => altered.finish(now: now), throwsFormatException);
    },
  );
  test('pages advance only through complete contiguous ranges', () {
    final data = fixture['manifest'] as Map<String, dynamic>;
    (data['entity_counts'] as Map<String, dynamic>)['SONG'] = 2;
    manifest = SnapshotManifest.decode(
      jsonEncode(data),
      expectedToken: token,
      now: now,
    );
    final first = songPage();
    first['next_cursor'] = 'sp1.next';
    expect(page(first).nextCursor, 'sp1.next');
    final second = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
    second['next_cursor'] = null;
    ((second['entries'] as List).single as Map<String, dynamic>)['ordinal'] = 2;
    expect(page(second, after: 1).entries.single.ordinal, 2);
    expect(() => page(second), throwsFormatException);
    expect(() => page(first, after: 1), throwsFormatException);
  });
  test('snapshot expiring during verification cannot be published', () {
    final verifier = SnapshotIntegrity(manifest);
    for (final data in fixture['pages'] as List) {
      for (final entry in page(data as Map<String, dynamic>).entries) {
        verifier.add(entry);
      }
    }
    expect(
      () => verifier.finish(now: manifest.expiresAt),
      throwsFormatException,
    );
  });
  test('verifier rejects duplicate and out of order rows', () {
    final entries = [
      for (final data in fixture['pages'] as List)
        ...page(data as Map<String, dynamic>).entries,
    ];
    final duplicate = SnapshotIntegrity(manifest)..add(entries.first);
    expect(() => duplicate.add(entries.first), throwsFormatException);
    expect(() => duplicate.add(entries.last), throwsFormatException);
    expect(() => duplicate.finish(now: now), throwsFormatException);
    final reversed = SnapshotIntegrity(manifest)..add(entries.last);
    expect(() => reversed.add(entries.first), throwsFormatException);
  });
}
