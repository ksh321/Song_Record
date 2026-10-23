import 'dart:convert';

import 'import_identity.dart';

final class ImportCandidateHold {
  ImportCandidateHold._(
    this.itemId,
    this.playlistId,
    this.code,
    Map<String, dynamic> row,
  ) : _source = jsonEncode(row);
  final String itemId, playlistId, code, _source;
  Map<String, dynamic> get original =>
      jsonDecode(_source) as Map<String, dynamic>;
  String get searchQuery {
    final snapshot = (original['payload'] as Map)['candidate_snapshot'];
    final title = snapshot is Map ? snapshot['title'] : null;
    return title is String ? String.fromCharCodes(title.runes.take(200)) : '';
  }

  String get reason => code == 'LEGACY_KY_CANDIDATE'
      ? '예전 백업의 금영 곡은 그대로 가져올 수 없어요. 같은 곡을 TJ에서 찾아 다시 선택해 주세요.'
      : '이 곡의 노래방 정보를 확인하지 못했어요. TJ에서 찾아 다시 선택해 주세요.';
  @override
  String toString() => 'ImportCandidateHold[$code]';
}

final class ImportCandidatePlan {
  ImportCandidatePlan._(
    List<Map<String, dynamic>> rows,
    List<ImportCandidateHold> held,
    Set<String> files,
  ) : _records = jsonEncode(rows),
      held = List.unmodifiable(held),
      fileIds = Set.unmodifiable(files);
  final String _records;
  final List<ImportCandidateHold> held;
  final Set<String> fileIds;
  List<Map<String, dynamic>> get records =>
      (jsonDecode(_records) as List).cast<Map<String, dynamic>>();
  @override
  String toString() => 'ImportCandidatePlan[REDACTED]';
}

/// Only legacy catalog candidates are held; no conversion or file discard.
ImportCandidatePlan planImportCandidates(
  ImportIdentityPlan identity, {
  required void Function() requireCurrent,
}) {
  requireCurrent();
  final rows = <Map<String, dynamic>>[], held = <ImportCandidateHold>[];
  for (final row in identity.records) {
    final payload = row['payload'] as Map<String, dynamic>;
    if (row['entity'] != 'PLAYLIST_ITEM' || payload['song_id'] != null) {
      rows.add(row);
      continue;
    }
    final snapshot = payload['candidate_snapshot'];
    final brand = payload['candidate_brand'];
    final legacy =
        brand == 'KY' ||
        snapshot is Map &&
            (snapshot['brand'] == 'KY' || snapshot['source_type'] == 'KY');
    if (legacy ||
        brand != 'TJ' ||
        snapshot is! Map ||
        (snapshot['brand'] != null && snapshot['brand'] != 'TJ')) {
      final list = payload['playlist_id'];
      if (list is! String) {
        throw const FormatException('Invalid held playlist reference');
      }
      held.add(
        ImportCandidateHold._(
          row['resource_id'] as String,
          list,
          legacy ? 'LEGACY_KY_CANDIDATE' : 'INVALID_CANDIDATE',
          row,
        ),
      );
      continue;
    }
    rows.add(row);
  }
  requireCurrent();
  return ImportCandidatePlan._(rows, held, identity.fileIds);
}
