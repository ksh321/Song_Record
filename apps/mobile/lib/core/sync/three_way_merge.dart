import 'dart:convert';

import '../database/local_models.dart';
import '../domain/identifiers.dart';

final class ThreeWayComparison {
  ThreeWayComparison(Map<String, dynamic> safe, List<Set<String>> conflicts)
    : _safe = canonicalJson(safe),
      conflicts = List.unmodifiable(conflicts.map(Set<String>.unmodifiable));
  final String _safe;
  final List<Set<String>> conflicts;
  Map<String, dynamic> get safePatch =>
      jsonDecode(_safe) as Map<String, dynamic>;
  bool get requiresChoice => conflicts.isNotEmpty;
  @override
  String toString() => 'ThreeWayComparison[REDACTED]';
}

/// Pure comparison only. Does not rewrite a queued operation, create a new
/// request, choose a conflict winner or use device timestamps.
ThreeWayComparison compareThreeWayPatch({
  required Map<String, dynamic>? base,
  required Map<String, dynamic> localChanges,
  required Map<String, dynamic> server,
  required Set<String> editableFields,
  List<Set<String>> atomicGroups = const [],
}) {
  const reserved = {
    'id',
    'user_id',
    'revision',
    'created_at',
    'updated_at',
    'deleted_at',
    'lifecycle_state',
  };
  if (editableFields.any(reserved.contains) ||
      localChanges.keys.any((k) => !editableFields.contains(k))) {
    throw const FormatException('Unexpected editable field');
  }
  final id = server['id'], revision = server['revision'];
  if (id is! String ||
      UuidValue(id).value != id ||
      revision is! int ||
      revision < 1 ||
      revision > 9223372036854775807) {
    throw const FormatException('Invalid server comparison identity');
  }
  if (base != null &&
      (base['id'] != id ||
          base['revision'] is! int ||
          (base['revision'] as int) < 1 ||
          (base['revision'] as int) > revision ||
          (base.containsKey('user_id') &&
              server.containsKey('user_id') &&
              base['user_id'] != server['user_id']))) {
    throw const FormatException('Comparison baseline changed');
  }
  bool equal(Object? a, Object? b) =>
      canonicalJson({'v': a}) == canonicalJson({'v': b});
  final grouped = <String>{};
  for (final group in atomicGroups) {
    if (group.length < 2 ||
        group.any(
          (key) => !editableFields.contains(key) || !grouped.add(key),
        )) {
      throw ArgumentError(
        'Atomic groups must be disjoint editable field groups',
      );
    }
  }
  final groups = <Set<String>>[
    ...atomicGroups.map((g) => g.toSet()),
    for (final key in editableFields)
      if (!grouped.contains(key)) {key},
  ];
  final safe = <String, dynamic>{}, conflicts = <Set<String>>[];
  for (final group in groups) {
    if (!group.any(localChanges.containsKey)) continue;
    // Absence is unknown, never an implicit null. Coupled fields are compared
    // together so independently safe edits cannot produce an invalid pair.
    if (base == null ||
        group.any((k) => !base.containsKey(k) || !server.containsKey(k))) {
      if (group.every(
        (k) =>
            localChanges.containsKey(k) &&
            server.containsKey(k) &&
            equal(localChanges[k], server[k]),
      )) {
        continue;
      }
      conflicts.add(group);
      continue;
    }
    final local = {
      for (final key in group)
        key: localChanges.containsKey(key) ? localChanges[key] : base[key],
    };
    if (group.every((k) => equal(local[k], base[k])) ||
        group.every((k) => equal(local[k], server[k]))) {
      continue;
    }
    if (group.every((k) => equal(base[k], server[k]))) {
      safe.addAll(local);
    } else {
      conflicts.add(group);
    }
  }
  return ThreeWayComparison(safe, conflicts);
}
