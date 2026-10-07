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
    this.serverJson,
    this.queueEvidence,
    this.pendingReview = false,
  }) : tagNames = Map.unmodifiable(tagNames),
       comparison =
           compareMetadataConflict(
             mutation,
             pendingReview: pendingReview,
             serverSnapshot: serverJson == null
                 ? null
                 : jsonDecode(serverJson) as Map<String, dynamic>,
           ) ??
           (throw StateError('This conflict needs another resolution path'));
  final QueuedMutation mutation;
  final String? localJson;
  final String? serverJson;
  final String? queueEvidence;
  final bool pendingReview;
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
    serverJson == null
        ? (jsonDecode(mutation.serverResponse!) as Map)['current'] as Map
        : jsonDecode(serverJson!) as Map,
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
