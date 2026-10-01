import 'dart:convert';

import '../database/local_models.dart';
import 'conflict_resolution_plan.dart';
import 'metadata_conflict.dart';
import 'three_way_merge.dart';

final class ConflictReview {
  ConflictReview(
    this.mutation,
    this.localJson, {
    Map<String, String> tagNames = const {},
  }) : tagNames = Map.unmodifiable(tagNames),
       comparison =
           compareMetadataConflict(mutation) ??
           (throw StateError('This conflict needs another resolution path'));
  final QueuedMutation mutation;
  final String? localJson;
  final ThreeWayComparison comparison;
  final Map<String, String> tagNames;

  String? tagName(String id, Map<String, dynamic> values) {
    if (values['tags'] case final List<dynamic> tags) {
      for (final tag in tags) {
        if (tag is Map && tag['id'] == id && tag['name_snapshot'] is String) {
          return tag['name_snapshot'] as String;
        }
      }
    }
    return tagNames[id];
  }

  Map<String, dynamic> get server => Map<String, dynamic>.from(
    (jsonDecode(mutation.serverResponse!) as Map)['current'] as Map,
  );
  Map<String, dynamic> get local => {
    ...jsonDecode(mutation.basePayload!) as Map<String, dynamic>,
    ...jsonDecode(mutation.payload) as Map<String, dynamic>,
  };
  @override
  String toString() => 'ConflictReview[REDACTED]';
}

abstract interface class ConflictActions {
  Future<ConflictReview> review(String opId);
  Future<void> resolve(
    ConflictReview review,
    Map<String, ConflictChoice> choices,
  );
}
