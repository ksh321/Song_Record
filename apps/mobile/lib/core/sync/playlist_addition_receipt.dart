import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'wire_json.dart';

bool isPlaylistAddition(MutationRequest request) =>
    request.mutation.entity == LocalEntity.playlist &&
    request.mutation.operation == LocalOperation.patch &&
    ((request.method == 'POST' &&
            request.path ==
                '/v1/playlists/${request.mutation.entityId}/items') ||
        isPlaylistLink(request));

bool isPlaylistLink(MutationRequest request) =>
    request.method == 'PATCH' &&
    RegExp(
      '^/v1/playlists/${request.mutation.entityId}/items/[0-9a-f-]{36}/song\$',
    ).hasMatch(request.path);

Map<String, dynamic> decodePlaylistAddition(
  MutationRequest request,
  MutationResponse response,
) {
  void require(bool value) {
    if (!value) {
      throw const FormatException('Invalid playlist addition receipt');
    }
  }

  require(isPlaylistAddition(request));
  final raw = decodeWireJson(response.body);
  require(raw is Map<String, dynamic>);
  final value = raw as Map<String, dynamic>;
  final link = isPlaylistLink(request);
  if (link) {
    require(
      value.length == 4 &&
          value.keys.every(
            {'playlist', 'items', 'item_id', 'changed'}.contains,
          ),
    );
    require(value['changed'] is bool && response.status == 200);
    value['created'] = value.remove('changed');
  }
  require(
    value.length == 4 &&
        value.keys.every({'playlist', 'items', 'item_id', 'created'}.contains),
  );
  require(
    value['playlist'] is Map<String, dynamic> &&
        value['items'] is List &&
        value['created'] is bool,
  );
  final parent = value['playlist'] as Map<String, dynamic>;
  validateChangePayload(LocalEntity.playlist, parent);
  require(
    parent['id'] == request.mutation.entityId && parent['deleted_at'] == null,
  );
  require(
    (link || value['created'] == (response.status == 201)) &&
        {200, 201}.contains(response.status),
  );
  require(
    parent['revision'] ==
        request.mutation.baseRevision + (value['created'] == true ? 1 : 0),
  );
  final itemId = value['item_id'];
  require(itemId is String && UuidValue(itemId).value == itemId);
  final selected = (value['items'] as List)
      .where((x) => x is Map && x['id'] == itemId)
      .toList();
  require(selected.length == 1);
  final sent = jsonDecode(request.body) as Map;
  final item = selected.single as Map;
  if (link) {
    require(
      request.path.endsWith('/items/$itemId/song') &&
          item['song_id'] == sent['song_id'],
    );
  }
  if (value['created'] == true) {
    require(item['song_id'] == sent['song_id']);
  }
  if (sent.containsKey('source_token')) {
    require(
      item['entry_key'] is String &&
          RegExp(r'^tj:\d{1,20}$').hasMatch(item['entry_key'] as String),
    );
    if (item['song_id'] == null) {
      final snapshot = item['candidate_snapshot'];
      require(item['candidate_brand'] == 'TJ' && snapshot is Map);
      final original = snapshot as Map;
      require(
        original['brand'] == 'TJ' &&
            original['number'] == item['candidate_number'] &&
            item['entry_key'] == 'tj:${item['candidate_number']}' &&
            original['title'] is String &&
            (original['title'] as String).trim().isNotEmpty &&
            original['artist'] is String &&
            (original['artist'] as String).trim().isNotEmpty,
      );
    }
  }
  return value;
}
