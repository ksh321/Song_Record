import 'package:flutter/foundation.dart';

import '../export/export_manifest.dart';
import 'import_validation.dart';

enum ImportDecisionPhase {
  ready,
  checking,
  checked,
  blocked,
  failed,
  approved,
  cancelled,
}

/// Explicit preview permission, never a claim that restore has been applied.
final class ImportConsent {
  ImportConsent._(
    this.source,
    this.partial,
    Set<String> files,
    this._generation,
  ) : fileIds = Set.unmodifiable(files);
  final ValidatedImport source;
  final bool partial;
  final Set<String> fileIds;
  final int _generation;
  @override
  String toString() => 'ImportConsent[REDACTED]';
}

final class ImportDecision extends ChangeNotifier {
  ImportDecision({required this.validate, required this.requireCurrent});
  final Future<ValidatedImport> Function(void Function() guard) validate;
  final void Function() requireCurrent;
  ImportDecisionPhase phase = ImportDecisionPhase.ready;
  ValidatedImport? _source;
  ImportConsent? _approval;
  int _generation = 0;
  bool _disposed = false;
  ValidatedImport? get source => _source;
  ImportConsent? get approval => _approval;
  bool get busy => phase == ImportDecisionPhase.checking;
  bool get canApproveWhole =>
      phase == ImportDecisionPhase.checked && _source!.wholeBackupValid;
  Set<String> get excludedFileIds => Set.unmodifiable({
    for (final issue in _source?.issues ?? const <ImportValidationIssue>[])
      if (issue.recordingId != null) issue.recordingId!,
  });
  Set<String> get normalFileIds {
    final excluded = excludedFileIds;
    return Set.unmodifiable({
      for (final file in _source?.manifest.files ?? const <ExportAudioEntry>[])
        if (file.included && !excluded.contains(file.recordingId))
          file.recordingId,
    });
  }

  bool get canApprovePartial {
    final value = _source;
    if (phase != ImportDecisionPhase.blocked ||
        value == null ||
        value.issues.isEmpty) {
      return false;
    }
    final included = {
      for (final f in value.manifest.files.where((f) => f.included))
        f.recordingId,
    };
    return value.issues.every(
      (e) =>
          e.recordingId != null &&
          included.contains(e.recordingId) &&
          {
            'MISSING_AUDIO',
            'AUDIO_HASH_OR_SIZE',
            'AUDIO_FORMAT',
            'AUDIO_INSPECTION_TIMEOUT',
          }.contains(e.code),
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (busy || _disposed) return;
    final generation = ++_generation;
    _source = null;
    _approval = null;
    phase = ImportDecisionPhase.checking;
    _changed();
    try {
      requireCurrent();
      void guard() {
        requireCurrent();
        if (_disposed || generation != _generation) {
          throw StateError('Import check cancelled');
        }
      }

      final result = await validate(guard);
      requireCurrent();
      if (_disposed || generation != _generation) return;
      _source = result;
      phase = result.wholeBackupValid
          ? ImportDecisionPhase.checked
          : ImportDecisionPhase.blocked;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _source = null;
      phase = ImportDecisionPhase.failed;
    }
    _changed();
  }

  ImportConsent approveWhole() {
    requireCurrent();
    if (!canApproveWhole) throw StateError('Whole import is not validated');
    return _approve(false);
  }

  /// Invoked only from the separate user choice. Never a fallback in check().
  ImportConsent approvePartial() {
    requireCurrent();
    if (!canApprovePartial) throw StateError('Partial import is not available');
    return _approve(true);
  }

  ImportConsent _approve(bool partial) {
    final result = ImportConsent._(
      _source!,
      partial,
      normalFileIds,
      _generation,
    );
    _approval = result;
    phase = ImportDecisionPhase.approved;
    _changed();
    return result;
  }

  void requireConsent(ImportConsent consent) {
    requireCurrent();
    if (_disposed ||
        phase != ImportDecisionPhase.approved ||
        !identical(_approval, consent) ||
        consent._generation != _generation) {
      throw StateError('Import choice changed or was cancelled');
    }
  }

  void cancel() {
    _generation++;
    _source = null;
    _approval = null;
    phase = ImportDecisionPhase.cancelled;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _source = null;
    _approval = null;
    super.dispose();
  }
}
