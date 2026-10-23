import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';
import 'change_payload_validation.dart';
import 'mutation_request.dart';
import 'wire_json.dart';

bool isPlaylistLibraryOrder(MutationRequest request) =>
    request.mutation.entity == LocalEntity.playlist &&
    request.method == 'PUT' &&
    request.path == '/v1/playlists/${request.mutation.entityId}/library-order';

bool validLibraryOrder(Map<String, dynamic> value, String anchor, int base) {
  if (value.length != 2 || value['base_revision'] != base || base < 1) {
    return false;
  }
  final rows = value['ordered_playlists'];
  if (rows is! List || rows.isEmpty || rows.length > 1000) return false;
  final ids = <String>{};
  var foundAnchor = false;
  for (final row in rows) {
    if (row is! Map ||
        row.length != 2 ||
        row['id'] is! String ||
        row['base_revision'] is! int ||
        (row['base_revision'] as int) < 1) {
      return false;
    }
    final id = UuidValue(row['id'] as String).value;
    if (!ids.add(id)) return false;
    if (id == anchor) foundAnchor = row['base_revision'] == base;
  }
  return foundAnchor;
}

List<Map<String, dynamic>> decodePlaylistLibraryOrder(
  MutationRequest request,
  MutationResponse response,
) {
  void require(bool condition) {
    if (!condition) {
      throw const FormatException('Invalid library order receipt');
    }
  }

  require(isPlaylistLibraryOrder(request) && response.status == 200);
  final sent = jsonDecode(request.body) as Map<String, dynamic>;
  require(
    validLibraryOrder(
      sent,
      request.mutation.entityId,
      request.mutation.baseRevision,
    ),
  );
  final raw = decodeWireJson(response.body);
  require(
    raw is Map &&
        raw.length == 2 &&
        raw['playlists'] is List &&
        raw['playlist'] is Map,
  );
  final expected = sent['ordered_playlists'] as List;
  final envelope = raw as Map<String, dynamic>;
  final incoming = envelope['playlists'] as List;
  require(expected.length == incoming.length);
  final values = <Map<String, dynamic>>[];
  for (var i = 0; i < incoming.length; i++) {
    require(incoming[i] is Map<String, dynamic>);
    final row = incoming[i] as Map<String, dynamic>;
    validateChangePayload(LocalEntity.playlist, row);
    require(
      row['id'] == expected[i]['id'] &&
          row['revision'] == expected[i]['base_revision'] + 1 &&
          row['display_order'] == i &&
          row['deleted_at'] == null,
    );
    values.add(row);
  }
  require(
    canonicalJson(envelope['playlist'] as Map<String, dynamic>) ==
        canonicalJson(
          values.singleWhere((r) => r['id'] == request.mutation.entityId),
        ),
  );
  return values;
}
