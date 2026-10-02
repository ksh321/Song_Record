import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/canonical_reference_plan.dart';

import 'canonical_song_store_test.dart' show uid;

void main() {
  final source = uid(10), canonical = uid(11), rec = uid(30);
  QueuedMutation request({
    LocalEntity entity = LocalEntity.recording,
    LocalOperation operation = LocalOperation.create,
    int revision = 0,
    String state = 'PENDING',
    int attempts = 0,
    String? base,
    Map<String, Object?>? body,
  }) => QueuedMutation(
    opId: uid(100),
    localOrder: 3,
    entity: entity,
    entityId: rec,
    operation: operation,
    state: state,
    baseRevision: revision,
    payload: canonicalJson(
      body ??
          {
            'id': rec,
            'song_id': source,
            'metadata_state': 'DRAFT',
            'note': 'private',
            'key_mode': 'MALE',
            'key_shift': -3,
            'version_code': 'LIVE',
          },
    ),
    basePayload: base,
    attemptCount: attempts,
  );
  MetadataCopy current({
    Object? selection,
    bool tombstone = false,
    int revision = 0,
    String? server,
  }) => MetadataCopy(
    revision: revision,
    tombstone: tombstone,
    serverJson: server,
    localJson: canonicalJson({
      'id': rec,
      'song_id': selection ?? canonical,
      'note': 'newer draft remains independent',
    }),
  );
  CanonicalReferencePlan? derive(
    QueuedMutation original, {
    MetadataCopy? copy,
    bool frozen = false,
  }) => CanonicalReferencePlan.derive(
    original: original,
    sourceId: source,
    canonicalId: canonical,
    current: copy ?? current(),
    hasFrozenRequest: frozen,
  );

  test(
    'CREATE substitutes only song identity and preserves original bytes',
    () {
      final original = request();
      final before = original.payload;
      expect(jsonDecode(derive(original)!.payloadJson), {
        ...jsonDecode(before) as Map<String, dynamic>,
        'song_id': canonical,
      });
      expect(original.payload, before);
      expect(original.attemptCount, 0);
    },
  );
  test(
    'dedicated relink retains the exact confirmed baseline and revision',
    () {
      final base = canonicalJson({'id': rec, 'revision': 4, 'song_id': source});
      final original = request(
        operation: LocalOperation.patch,
        revision: 4,
        base: base,
        body: {'base_revision': 4, 'song_id': source},
      );
      expect(
        jsonDecode(
          derive(
            original,
            copy: current(revision: 4, server: base),
          )!.payloadJson,
        ),
        {'base_revision': 4, 'song_id': canonical},
      );
      expect(original.basePayload, base);
      expect(
        derive(original, copy: current(revision: 5, server: base)),
        isNull,
      );
      expect(
        derive(
          original,
          copy: current(
            revision: 4,
            server: canonicalJson({
              'id': rec,
              'revision': 4,
              'song_id': uid(99),
            }),
          ),
        ),
        isNull,
      );
    },
  );
  test('offline relink keeps base zero until real CREATE ACK', () {
    final original = request(
      operation: LocalOperation.patch,
      body: {'base_revision': 0, 'song_id': source},
    );
    expect(jsonDecode(derive(original)!.payloadJson), {
      'base_revision': 0,
      'song_id': canonical,
    });
  });
  test(
    'playlist reference preserves identity order and unknown local fields',
    () {
      final original = request(
        entity: LocalEntity.playlistItem,
        body: {
          'id': rec,
          'playlist_id': uid(50),
          'song_id': source,
          'position': 7,
          'entry_key': 'tj:12345',
        },
      );
      expect(jsonDecode(derive(original)!.payloadJson), {
        ...jsonDecode(original.payload) as Map<String, dynamic>,
        'song_id': canonical,
      });
    },
  );
  for (final state in ['SENDING', 'RETRY', 'CONFLICT', 'FAILED', 'ACKED']) {
    test('$state is never replaced', () {
      expect(derive(request(state: state)), isNull);
    });
  }
  test('attempt or frozen wire independently prevents a replacement', () {
    expect(derive(request(attempts: 1)), isNull);
    expect(derive(request(), frozen: true), isNull);
  });
  test('explicit disconnect other selection and tombstones are preserved', () {
    expect(
      derive(
        request(),
        copy: const MetadataCopy(
          revision: 0,
          tombstone: false,
          localJson: '{"song_id":null}',
        ),
      ),
      isNull,
    );
    expect(derive(request(), copy: current(selection: uid(99))), isNull);
    expect(derive(request(), copy: current(tombstone: true)), isNull);
    expect(
      derive(
        request(),
        copy: const MetadataCopy(revision: 0, tombstone: false),
      ),
      isNull,
    );
  });
  test(
    'mixed patches unknown recording fields and malformed references stay held',
    () {
      expect(
        derive(
          request(
            operation: LocalOperation.patch,
            body: {'base_revision': 0, 'song_id': source, 'note': 'keep'},
          ),
        ),
        isNull,
      );
      expect(
        derive(
          request(
            body: {
              'id': rec,
              'song_id': source,
              'metadata_state': 'DRAFT',
              'unknown': true,
            },
          ),
        ),
        isNull,
      );
      expect(
        derive(
          request(
            entity: LocalEntity.playlistItem,
            body: {'id': rec, 'song_id': source, 'playlist_id': 'bad'},
          ),
        ),
        isNull,
      );
      expect(
        derive(
          request(
            body: {'id': uid(99), 'song_id': source, 'metadata_state': 'DRAFT'},
          ),
        ),
        isNull,
      );
    },
  );
}
