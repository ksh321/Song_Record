import 'dart:convert';

import '../database/local_models.dart';

enum DispatchWaitReason {
  earlierMutation,
  queueState,
  missingDependency,
  deletedTarget,
  unresolvedBaseline,
  staleBaseline,
  unsupported,
  invalidPayload,
  mappingBlocked,
  superseded,
}

final class DispatchWait {
  const DispatchWait(this.reason, {this.dependency});
  final DispatchWaitReason reason;
  final LocalTarget? dependency;
}

/// Eligibility only: no network, queue acknowledgement, payload rewrite or
/// file deletion. Rebuild after each committed response or account change.
final class DispatchPlan {
  DispatchPlan({
    required List<QueuedMutation> ready,
    required Map<String, DispatchWait> waiting,
  }) : ready = List.unmodifiable(ready),
       waiting = Map.unmodifiable(waiting);

  final List<QueuedMutation> ready;
  final Map<String, DispatchWait> waiting;
}

final class DependencyPlanner {
  const DependencyPlanner();

  DispatchPlan plan(DispatchSnapshot snapshot) {
    final mapping = snapshot.mapping;

    int compareOrder(QueuedMutation a, QueuedMutation b) {
      final logical = mapping.orderOf(a).compareTo(mapping.orderOf(b));
      return logical != 0 ? logical : a.localOrder.compareTo(b.localOrder);
    }

    final ordered = [...snapshot.pending]..sort(compareOrder);
    final firstByTarget = <LocalTarget>{};
    final ready = <QueuedMutation>[];
    final waiting = <String, DispatchWait>{};

    for (final mutation in ordered) {
      if (mutation.state == 'ACKED') continue;

      if (mapping.superseded.contains(mutation.opId)) {
        waiting[mutation.opId] = const DispatchWait(
          DispatchWaitReason.superseded,
        );
        continue;
      }

      final target = LocalTarget(mutation.entity, mutation.entityId);
      final group = mapping.groupOf(target);
      if (!firstByTarget.add(group)) {
        waiting[mutation.opId] = const DispatchWait(
          DispatchWaitReason.earlierMutation,
        );
        continue;
      }

      // Reserve the group's head before evaluating a hold. Filtering a held
      // mutation out of the input would incorrectly release younger aliases.
      final wait = _wait(mutation, target, snapshot);
      if (wait == null) {
        ready.add(mutation);
      } else {
        waiting[mutation.opId] = wait;
      }
    }

    ready.sort((a, b) {
      final phase = _phase(a.entity).compareTo(_phase(b.entity));
      return phase != 0 ? phase : compareOrder(a, b);
    });
    return DispatchPlan(ready: ready, waiting: waiting);
  }

  DispatchWait? _wait(
    QueuedMutation mutation,
    LocalTarget target,
    DispatchSnapshot snapshot,
  ) {
    if (!snapshot.mapping.allows(mutation.opId)) {
      return const DispatchWait(DispatchWaitReason.mappingBlocked);
    }
    if (mutation.state != 'PENDING') {
      return const DispatchWait(DispatchWaitReason.queueState);
    }
    // Replay only an already-sent, validated immutable wire request. New edits
    // still require the latest baseline and all dependency checks below.
    if (mutation.attemptCount > 0 &&
        snapshot.frozenRetries.contains(mutation.opId)) {
      return null;
    }
    if (_phase(mutation.entity) < 0 ||
        !({
              LocalOperation.create,
              LocalOperation.patch,
            }.contains(mutation.operation) ||
            mutation.entity == LocalEntity.playlist &&
                mutation.operation == LocalOperation.purge)) {
      return const DispatchWait(DispatchWaitReason.unsupported);
    }
    final baseline = snapshot.baselines[target];
    if (baseline?.tombstone == true) {
      return DispatchWait(DispatchWaitReason.deletedTarget, dependency: target);
    }
    if (mutation.operation != LocalOperation.create) {
      if (mutation.baseRevision == 0 ||
          baseline == null ||
          baseline.revision == 0) {
        return DispatchWait(
          DispatchWaitReason.unresolvedBaseline,
          dependency: target,
        );
      }
      // A newer received server copy must not strand an older offline edit.
      // Send its unchanged positive base_revision to the server, which returns
      // the authoritative 409/current snapshot for explicit conflict review.
      // A local revision ahead of the known server is still unresolved.
      if (mutation.baseRevision > baseline.revision) {
        return DispatchWait(
          DispatchWaitReason.staleBaseline,
          dependency: target,
        );
      }
    } else if (mutation.baseRevision != 0) {
      return const DispatchWait(DispatchWaitReason.invalidPayload);
    }
    try {
      final Object? decoded = jsonDecode(mutation.payload);
      if (decoded is! Map<String, Object?>) {
        return const DispatchWait(DispatchWaitReason.invalidPayload);
      }
      if (mutation.operation != LocalOperation.create &&
          decoded['base_revision'] != mutation.baseRevision) {
        return const DispatchWait(DispatchWaitReason.invalidPayload);
      }
      // Legacy local RECORDING_CONDITION has not yet been migrated to the
      // server CONDITION definition. Do not guess a custom condition mapping.
      final condition = decoded['condition_code'];
      if (mutation.entity == LocalEntity.recording &&
          condition != null &&
          !{'VERY_GOOD', 'GOOD', 'NORMAL', 'BAD'}.contains(condition)) {
        return const DispatchWait(DispatchWaitReason.unsupported);
      }
      for (final dependency in _dependencies(mutation.entity, decoded)) {
        final known = snapshot.baselines[dependency];
        if (known?.tombstone == true) {
          // P10-09: send the original new draft unchanged. The server confirms
          // ownership/deletion and stores it unlinked; never rewrite a frozen
          // request or revive the deleted song. Existing-recording edits still
          // wait, and all other dependencies are checked normally.
          if (mutation.entity == LocalEntity.recording &&
              mutation.operation == LocalOperation.create &&
              decoded['metadata_state'] == 'DRAFT' &&
              decoded['id'] == mutation.entityId &&
              dependency.entity == LocalEntity.song &&
              decoded['song_id'] == dependency.id) {
            continue;
          }
          return DispatchWait(
            DispatchWaitReason.deletedTarget,
            dependency: dependency,
          );
        }
        if (known == null || known.revision == 0) {
          return DispatchWait(
            DispatchWaitReason.missingDependency,
            dependency: dependency,
          );
        }
      }
    } on FormatException {
      return const DispatchWait(DispatchWaitReason.invalidPayload);
    } on ArgumentError {
      return const DispatchWait(DispatchWaitReason.invalidPayload);
    }
    return null;
  }

  List<LocalTarget> _dependencies(
    LocalEntity entity,
    Map<String, Object?> body,
  ) {
    final result = <LocalTarget>[];
    void add(String field, LocalEntity type, {bool mandatory = false}) {
      final value = body[field];
      if (value == null && !mandatory) return;
      if (value is! String) throw const FormatException('Invalid reference');
      result.add(LocalTarget(type, value));
    }

    switch (entity) {
      case LocalEntity.song:
        add('representative_recording_id', LocalEntity.recording);
      case LocalEntity.recording:
        add('song_id', LocalEntity.song);
        final tags = body['tag_ids'];
        if (tags != null) {
          if (tags is! List<Object?>) {
            throw const FormatException('Invalid tags');
          }
          for (final tag in tags) {
            if (tag is! String) throw const FormatException('Invalid tag');
            result.add(LocalTarget(LocalEntity.tag, tag));
          }
        }
      case LocalEntity.playlistItem:
        add('playlist_id', LocalEntity.playlist, mandatory: true);
        add('song_id', LocalEntity.song, mandatory: true);
      case LocalEntity.playlist:
        if (body.containsKey('song_ids')) {
          final ids = body['song_ids'];
          if (ids is! List || ids.any((id) => id is! String)) {
            throw const FormatException('Invalid song references');
          }
          for (final id in ids) {
            result.add(LocalTarget(LocalEntity.song, id as String));
          }
        }
        if (body.containsKey('song_id')) {
          add('song_id', LocalEntity.song, mandatory: true);
        }
      case LocalEntity.recordingTag:
        add('recording_id', LocalEntity.recording, mandatory: true);
        add('tag_id', LocalEntity.tag, mandatory: true);
      default:
        break;
    }
    return result;
  }

  int _phase(LocalEntity entity) => switch (entity) {
    LocalEntity.song || LocalEntity.tag => 0,
    LocalEntity.recording => 1,
    LocalEntity.playlist ||
    LocalEntity.playlistItem ||
    LocalEntity.recordingTag => 2,
    _ => -1,
  };
}
