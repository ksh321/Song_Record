import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/metadata_response.dart';
import 'package:song_record/core/sync/mutation_request.dart';

void main() {
  test('existing playlist UUID accepts server baseline for explicit conflict review', () {
    const id = '00000000-0000-4000-8000-000000001901';
    final mutation = QueuedMutation(
      opId: '00000000-0000-4000-8000-000000001902',
      localOrder: 1,
      entity: LocalEntity.playlist,
      entityId: id,
      operation: LocalOperation.create,
      state: 'IN_FLIGHT',
      baseRevision: 0,
      payload: jsonEncode({'id': id, 'name': 'local'}),
      attemptCount: 1,
    );
    final request = MutationRequest.prepare(mutation)!;
    final existing = {
      'id': id,
      'name': 'server kept',
      'revision': 7,
      'deleted_at': null,
      'updated_at': '2026-10-11T00:00:00Z',
    };
    expect(
      decodeMetadataSnapshot(
        request,
        MutationResponse(200, jsonEncode(existing)),
      ),
      existing,
    );
    expect(
      () => decodeMetadataSnapshot(
        request,
        MutationResponse(201, jsonEncode(existing)),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeMetadataSnapshot(
        request,
        MutationResponse(200, jsonEncode({...existing, 'id': 'invalid'})),
      ),
      throwsFormatException,
    );
  });
}
