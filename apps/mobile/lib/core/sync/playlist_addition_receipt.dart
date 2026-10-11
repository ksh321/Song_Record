import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'wire_json.dart';

bool isPlaylistAddition(MutationRequest request) =>
    request.mutation.entity == LocalEntity.playlist &&
    request.mutation.operation == LocalOperation.patch &&
    request.method == 'POST' &&
    request.path == '/v1/playlists/${request.mutation.entityId}/items';

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
    value['created'] == (response.status == 201) &&
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
  if (value['created'] == true) {
    require((selected.single as Map)['song_id'] == sent['song_id']);
  }
  return value;
}
