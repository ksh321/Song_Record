import 'dart:convert';

import '../database/local_models.dart';

/// RecordingDrafts emits core fields; RecordingSaving adds file, while
/// RecordingEditing/Rating/Linking add tier and tags. Absence of these optional
/// projections is not deletion. Explicit null/empty values still take effect.
Map<String, dynamic> projectRecordingChange(
  Map<String, dynamic>? previous,
  Map<String, dynamic> incoming,
) {
  final result = jsonDecode(jsonEncode(incoming)) as Map<String, dynamic>;
  if (previous != null && previous['id'] != incoming['id']) {
    throw const FormatException('Recording projection identity changed');
  }
  if (incoming.containsKey('tag_ids') != incoming.containsKey('tags')) {
    throw const FormatException('Incomplete recording tag projection');
  }
  for (final key in ['file', 'tier', 'tag_ids', 'tags']) {
    if (!result.containsKey(key) && previous?.containsKey(key) == true) {
      result[key] = jsonDecode(jsonEncode(previous![key]));
    }
  }
  if (result.containsKey('file') && result['file'] is! Map<String, dynamic>) {
    throw const FormatException('Invalid recording file projection');
  }
  if (previous?['file'] is Map<String, dynamic> &&
      incoming['file'] is Map<String, dynamic> &&
      canonicalJson(previous!['file'] as Map<String, dynamic>) !=
          canonicalJson(incoming['file'] as Map<String, dynamic>)) {
    throw const FormatException('Immutable recording file projection changed');
  }
  return result;
}
