import 'dart:convert';

import 'package:drift/drift.dart';

import '../sync/mutation_request.dart';
import '../sync/playlist_library_order_receipt.dart';
import 'account_database.dart';
import 'local_models.dart';

Future<MappingEligibility> playlistOrderDismissalEligibility(
  AccountDatabase db,
  MappingEligibility mapping,
) async {
  final records = await db.customSelect('''SELECT d.*,m.entity_type,m.entity_id,
    m.operation,m.queue_state,m.base_revision,m.payload,m.attempt_count,
    m.request_hash AS original_hash,m.server_response,m.user_id AS original_owner,
    m.rowid AS local_order FROM playlist_order_dismissals d
    JOIN local_mutations m ON m.op_id=d.op_id''').get();
  final blocked = {...mapping.blocked}, superseded = {...mapping.superseded};
  for (final row in records) {
    final op = row.read<String>('op_id');
    try {
      final response = jsonDecode(row.read<String>('response_json')) as Map;
      final payload =
          jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
      if (row.read<String>('user_id') != db.userId ||
          row.read<String>('original_owner') != db.userId ||
          row.read<String>('entity_type') != 'PLAYLIST' ||
          row.read<String>('operation') != 'PATCH' ||
          row.read<String>('queue_state') != 'CONFLICT' ||
          response['status'] != 409 ||
          response['code'] != 'PLAYLIST_ORDER_CHANGED' ||
          row.read<String>('request_hash') !=
              row.read<String>('original_hash') ||
          row.read<String>('response_json') !=
              row.read<String>('server_response') ||
          !validLibraryOrder(
            payload,
            row.read<String>('entity_id'),
            row.read<int>('base_revision'),
          )) {
        throw const FormatException('Order decision evidence mismatch');
      }
      superseded.add(op);
    } catch (_) {
      blocked.add(op);
    }
  }
  return MappingEligibility(
    blocked: blocked,
    superseded: superseded,
    logicalOrders: mapping.logicalOrders,
    groups: mapping.groups,
  );
}

Future<void> dismissPlaylistOrder(
  AccountDatabase db,
  QueuedMutation expected,
  int now,
) async {
  final request = MutationRequest.prepare(expected);
  if (request == null ||
      !isPlaylistLibraryOrder(request) ||
      expected.state != 'CONFLICT') {
    throw StateError('Not a rejected playlist order');
  }
  if (await db
          .customSelect(
            'SELECT op_id FROM playlist_order_dismissals WHERE op_id=?',
            variables: [Variable(expected.opId)],
          )
          .getSingleOrNull() !=
      null) {
    throw StateError('Order decision exists');
  }
  final row = await db
      .customSelect(
        'SELECT * FROM local_mutations WHERE op_id=? AND user_id=?',
        variables: [Variable(expected.opId), Variable(db.userId)],
      )
      .getSingle();
  if (row.read<String>('entity_type') != expected.entity.code ||
      row.read<String>('entity_id') != expected.entityId ||
      row.read<String>('operation') != expected.operation.code ||
      row.read<int>('base_revision') != expected.baseRevision ||
      row.readNullable<String>('base_payload') != expected.basePayload ||
      row.read<String>('payload') != expected.payload ||
      row.read<int>('attempt_count') != expected.attemptCount ||
      row.read<String>('server_response') != expected.serverResponse ||
      row.read<String>('queue_state') != 'CONFLICT') {
    throw StateError('Order decision changed');
  }
  await db.customStatement(
    'INSERT INTO playlist_order_dismissals VALUES(?,?,?,?,?)',
    [
      expected.opId,
      db.userId,
      row.read<String>('request_hash'),
      expected.serverResponse,
      now,
    ],
  );
  // The order command has no field draft. Only release its unchanged baseline;
  // an unrelated later edit remains intact.
  final decisions = await playlistOrderDismissalEligibility(
    db,
    const MappingEligibility.empty(),
  );
  final retired = decisions.superseded.difference(decisions.blocked);
  final otherWork = await db
      .customSelect(
        "SELECT op_id FROM local_mutations WHERE entity_type='PLAYLIST' AND entity_id=? AND queue_state<>'ACKED'",
        variables: [Variable(expected.entityId)],
      )
      .get();
  final keepOther = otherWork.any(
    (row) => !retired.contains(row.read<String>('op_id')),
  );
  await db.customStatement(
    '''UPDATE metadata_copies SET local_payload=server_payload
    WHERE user_id=? AND entity_type='PLAYLIST' AND entity_id=? AND local_payload=?
    AND ?=0''',
    [db.userId, expected.entityId, expected.basePayload, keepOther ? 1 : 0],
  );
}
