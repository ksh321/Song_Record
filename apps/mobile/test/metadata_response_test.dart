import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/metadata_response.dart';
import 'package:song_record/core/sync/mutation_request.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

const timestamp = '2026-09-29T00:00:00Z';

MutationRequest request({
  LocalEntity entity = LocalEntity.song,
  LocalOperation operation = LocalOperation.create,
  String sourceType = 'TJ',
  String? body,
  String? payload,
  String? method,
  String? path,
}) {
  final wire =
      body ??
      jsonEncode({
        'id': id(10),
        'source_type': sourceType,
        'source_token': 'opaque-proof-not-the-tj-number',
      });
  return MutationRequest(
    mutation: QueuedMutation(
      opId: id(1),
      localOrder: 1,
      entity: entity,
      entityId: id(10),
      operation: operation,
      state: 'SENDING',
      baseRevision: operation == LocalOperation.create ? 0 : 5,
      payload: payload ?? wire,
      attemptCount: 0,
    ),
    method: method ?? (operation == LocalOperation.create ? 'POST' : 'PATCH'),
    path: path ?? '/v1/songs',
    body: wire,
    attempt: 1,
  );
}

Map<String, Object?> song({String? target, int revision = 4}) => {
  'id': target ?? id(11),
  'revision': revision,
  'updated_at': timestamp,
  'source_type': 'TJ',
  'tj_number': '12345',
  'title': 'server song',
  'artist': 'server artist',
  'version_code': 'NORMAL',
  'tier': null,
  'note': '',
  'lifecycle_state': 'ACTIVE',
  'representative_recording_id': null,
  'representative_key_mode': null,
  'representative_key_shift': null,
};

Map<String, Object?> recording({int revision = 4}) => {
  'id': id(10),
  'metadata_state': 'DRAFT',
  'song_id': null,
  'title_snapshot': null,
  'artist_snapshot': null,
  'version_code': 'NORMAL',
  'key_mode': null,
  'key_shift': null,
  'note': '',
  'recorded_at': timestamp,
  'timezone_id': 'UTC',
  'timezone_offset_minutes': 0,
  'origin_device_id': id(2),
  'revision': revision,
  'link_revision': 1,
  'updated_at': timestamp,
  'lifecycle_state': 'ACTIVE',
  'condition_code': null,
  'condition_name_snapshot': null,
  'tier': null,
  'tag_ids': <String>[id(20)],
  'tags': <Map<String, Object?>>[
    {'id': id(20), 'name_snapshot': 'tag'},
  ],
};

MutationResponse creation({
  Map<String, Object?>? snapshot,
  int status = 200,
  bool created = false,
  String? canonicalId,
}) {
  final value = snapshot ?? song();
  return MutationResponse(
    status,
    jsonEncode({
      'created': created,
      'canonical_song_id': canonicalId ?? value['id'],
      'song': value,
    }),
  );
}

void main() {
  test('canonical receipt retains wire identity and exact envelope text', () {
    final r = request();
    final body =
        ' \n${const JsonEncoder.withIndent('  ').convert({'created': false, 'canonical_song_id': id(11), 'song': song()})}\n ';
    final receipt = CanonicalSongReceipt.decode(r, MutationResponse(200, body));

    expect(identical(receipt.request, r), isTrue);
    expect(receipt.status, 200);
    expect(receipt.localSongId, id(10));
    expect(receipt.canonicalSongId, id(11));
    expect(receipt.envelopeBody, body);
    expect(receipt.snapshot, song());
    expect(() => receipt.snapshot['title'] = 'changed', throwsUnsupportedError);
    expect(() => receipt.snapshot.remove('note'), throwsUnsupportedError);
    expect(() => receipt.snapshot.clear(), throwsUnsupportedError);
    expect(receipt.toString(), 'CanonicalSongReceipt[REDACTED]');

    // The token is intentionally unrelated to the TJ number.
    expect(jsonDecode(r.body)['source_token'], isNot('12345'));
    expect(receipt.snapshot['tj_number'], '12345');
  });

  test('eligibility uses frozen wire body rather than queue payload', () {
    final manualPayload = jsonEncode({'id': id(10), 'source_type': 'MANUAL'});
    final tjPayload = request().body;

    expect(
      CanonicalSongReceipt.decode(
        request(payload: manualPayload),
        creation(),
      ).canonicalSongId,
      id(11),
    );
    expect(
      () => CanonicalSongReceipt.decode(
        request(sourceType: 'MANUAL', payload: tjPayload),
        creation(),
      ),
      throwsFormatException,
    );
  });

  final invalidRequests = <String, MutationRequest>{
    'TAG CREATE': request(entity: LocalEntity.tag),
    'SONG PATCH': request(operation: LocalOperation.patch),
    'MANUAL wire': request(sourceType: 'MANUAL'),
    'wrong method': request(method: 'PATCH'),
    'wrong route': request(path: '/v1/tags'),
    'malformed wire': request(body: '{'),
    'array wire': request(body: '[]'),
    'missing source': request(body: jsonEncode({'id': id(10)})),
    'missing wire id': request(body: '{"source_type":"TJ"}'),
    'different wire id': request(
      body: jsonEncode({'id': id(12), 'source_type': 'TJ'}),
    ),
  };
  for (final entry in invalidRequests.entries) {
    test('receipt rejects ${entry.key}', () {
      expect(
        () => CanonicalSongReceipt.decode(entry.value, creation()),
        throwsFormatException,
      );
    });
  }

  final invalidResponses = <String, MutationResponse>{
    '201 created true': creation(
      status: 201,
      created: true,
      snapshot: song(revision: 1),
    ),
    '201 created false': creation(status: 201),
    '200 created true': creation(created: true),
    '409': creation(status: 409),
    'same canonical ID': creation(snapshot: song(target: id(10))),
    'canonical envelope mismatch': creation(canonicalId: id(12)),
    'MANUAL snapshot': creation(snapshot: {...song(), 'source_type': 'MANUAL'}),
    'null TJ number': creation(snapshot: {...song(), 'tj_number': null}),
    'empty TJ number': creation(snapshot: {...song(), 'tj_number': ''}),
    'numeric TJ number': creation(snapshot: {...song(), 'tj_number': 12345}),
    'nondigit TJ number': creation(snapshot: {...song(), 'tj_number': 'abc'}),
    'long TJ number': creation(snapshot: {...song(), 'tj_number': '1' * 21}),
    'untrimmed TJ number': creation(
      snapshot: {...song(), 'tj_number': ' 12345'},
    ),
    'inactive snapshot': creation(
      snapshot: {...song(), 'lifecycle_state': 'TRASHED'},
    ),
    'malformed JSON': const MutationResponse(200, '{'),
    'array envelope': const MutationResponse(200, '[]'),
    'missing created': MutationResponse(
      200,
      jsonEncode({'canonical_song_id': id(11), 'song': song()}),
    ),
    'missing canonical ID': MutationResponse(
      200,
      jsonEncode({'created': false, 'song': song()}),
    ),
    'nonboolean created': MutationResponse(
      200,
      jsonEncode({
        'created': 'false',
        'canonical_song_id': id(11),
        'song': song(),
      }),
    ),
    'unexpected envelope field': MutationResponse(
      200,
      jsonEncode({
        'created': false,
        'canonical_song_id': id(11),
        'song': song(),
        'extra': true,
      }),
    ),
  };
  for (final entry in invalidResponses.entries) {
    test('receipt rejects ${entry.key}', () {
      expect(
        () => CanonicalSongReceipt.decode(request(), entry.value),
        throwsFormatException,
      );
    });
  }

  // Every field in this minimal valid SONG snapshot is required by the
  // existing validator, including the explicit-null representative fields.
  for (final field in song().keys) {
    test('receipt rejects missing SONG field $field', () {
      final incomplete = song()..remove(field);
      expect(
        () => CanonicalSongReceipt.decode(
          request(),
          creation(snapshot: incomplete),
        ),
        throwsFormatException,
      );
    });
  }

  final invalidFields = <String, Object?>{
    'revision': 0,
    'updated_at': 'not-a-date',
    'title': 123,
    'artist': null,
    'version_code': null,
    'tier': <String>[],
    'note': <String, Object?>{},
    'representative_key_mode': 1,
    'representative_key_shift': '1',
    'created_at': 'not-a-date',
    'latest_recorded_at': 'not-a-date',
    'unexpected': true,
  };
  for (final entry in invalidFields.entries) {
    test('receipt preserves full validation of ${entry.key}', () {
      expect(
        () => CanonicalSongReceipt.decode(
          request(),
          creation(snapshot: {...song(), entry.key: entry.value}),
        ),
        throwsFormatException,
      );
    });
  }

  for (final field in ['id', 'representative_recording_id']) {
    test('receipt rejects malformed UUID in $field', () {
      expect(
        () => CanonicalSongReceipt.decode(
          request(),
          creation(snapshot: {...song(), field: 'not-a-uuid'}),
        ),
        throwsFormatException,
      );
    });
  }

  test('shared decoder retains SONG create success and duplicate shapes', () {
    final created = song(target: id(10), revision: 1);
    expect(
      decodeMetadataSnapshot(
        request(),
        creation(snapshot: created, status: 201, created: true),
      ),
      created,
    );

    // The shared decoder leaves same-ID duplicate policy to the dispatcher.
    final existing = song(target: id(10));
    expect(
      decodeMetadataSnapshot(request(), creation(snapshot: existing)),
      existing,
    );
    expect(decodeMetadataSnapshot(request(), creation()), song());
    expect(
      () => decodeMetadataSnapshot(
        request(),
        creation(status: 201, created: true),
      ),
      throwsFormatException,
    );
  });

  test('shared decoder retains TAG create acknowledgement', () {
    final snapshot = <String, Object?>{
      'id': id(10),
      'name': 'tag',
      'revision': 1,
      'archived_at': null,
      'updated_at': timestamp,
    };
    expect(
      decodeMetadataSnapshot(
        request(entity: LocalEntity.tag),
        MutationResponse(201, jsonEncode(snapshot)),
      ),
      snapshot,
    );
  });

  final patchSnapshots = <LocalEntity, Map<String, Object?>>{
    LocalEntity.song: song(target: id(10), revision: 6),
    LocalEntity.tag: {
      'id': id(10),
      'name': 'tag',
      'revision': 6,
      'archived_at': null,
      'updated_at': timestamp,
    },
    LocalEntity.recording: recording(revision: 6),
  };
  for (final entry in patchSnapshots.entries) {
    test('${entry.key.code} preserves PATCH and older conflict validation', () {
      final r = request(entity: entry.key, operation: LocalOperation.patch);

      expect(
        decodeMetadataSnapshot(
          r,
          MutationResponse(200, jsonEncode(entry.value)),
        ),
        entry.value,
      );
      final older = {...entry.value, 'revision': 4};
      expect(
        () =>
            decodeMetadataSnapshot(r, MutationResponse(200, jsonEncode(older))),
        throwsFormatException,
      );
      expect(
        decodeMetadataSnapshot(
          r,
          MutationResponse(409, jsonEncode(older)),
          conflict: true,
        ),
        older,
      );
      expect(
        () => decodeMetadataSnapshot(
          r,
          MutationResponse(409, jsonEncode({...older, 'id': id(12)})),
          conflict: true,
        ),
        throwsFormatException,
      );
    });
  }

  test('conflict retains non-ACTIVE snapshot while success rejects it', () {
    final r = request(operation: LocalOperation.patch);
    final inactive = {...song(target: id(10)), 'lifecycle_state': 'TRASHED'};
    expect(
      decodeMetadataSnapshot(
        r,
        MutationResponse(409, jsonEncode(inactive)),
        conflict: true,
      ),
      inactive,
    );
    expect(
      () => decodeMetadataSnapshot(
        r,
        MutationResponse(200, jsonEncode({...inactive, 'revision': 6})),
      ),
      throwsFormatException,
    );
  });

  for (final field in [
    'condition_code',
    'condition_name_snapshot',
    'tags',
    'tag_ids',
    'tier',
  ]) {
    test('RECORDING PATCH retains required field $field', () {
      final incomplete = recording(revision: 6)..remove(field);
      expect(
        () => decodeMetadataSnapshot(
          request(
            entity: LocalEntity.recording,
            operation: LocalOperation.patch,
          ),
          MutationResponse(200, jsonEncode(incomplete)),
        ),
        throwsFormatException,
      );
    });
  }

  test('RECORDING PATCH rejects incomplete tag snapshot', () {
    final invalid = recording(revision: 6)
      ..['tags'] = [
        {'id': id(20)},
      ];
    expect(
      () => decodeMetadataSnapshot(
        request(entity: LocalEntity.recording, operation: LocalOperation.patch),
        MutationResponse(200, jsonEncode(invalid)),
      ),
      throwsFormatException,
    );
  });

  for (final field in ['condition_code', 'condition_name_snapshot']) {
    test('RECORDING CREATE retains explicit-null requirement for $field', () {
      final incomplete = recording(revision: 1)..remove(field);
      expect(
        () => decodeMetadataSnapshot(
          request(entity: LocalEntity.recording),
          MutationResponse(201, jsonEncode(incomplete)),
        ),
        throwsFormatException,
      );
    });
  }
}
