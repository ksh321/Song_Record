import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/database/account_store.dart';
import '../../core/database/local_models.dart';
import '../../core/sync/canonical_conflict_plan.dart';
import '../../core/sync/conflict_review.dart';
import '../../core/sync/local_repository.dart';
import '../../core/sync/mutation_transport.dart';
import '../../core/uploads/upload_dispatcher.dart';
import '../auth/auth_session.dart';

final class SyncItem {
  const SyncItem(this.mutation, this.retry, {this.pendingReview = false});
  final QueuedMutation mutation;
  final RetryStatus? retry;
  final bool pendingReview;
}

abstract interface class SyncBackend {
  bool get automaticFollowupAllowed;
  Future<List<SyncItem>> load();
  Future<void> send();
  Future<bool> retry(String opId, int expectedAttempt);
  Future<DateTime?> nextAttempt();
}

abstract interface class SyncStatusSource {
  String? get statusMessage;
}

final class RepositorySyncBackend implements SyncBackend, SyncStatusSource {
  RepositorySyncBackend(
    this.repository,
    this.transport,
    this.session, {
    this.uploads,
  });
  final UploadDispatcher? uploads;
  final LocalRepository repository;
  final MutationTransport transport;
  final Future<AuthSession> Function() session;
  bool _authenticationBlocked = false;
  int _unlinkedRecordings = 0;
  @override
  String? get statusMessage => _unlinkedRecordings == 0
      ? null
      : '곡이 삭제되어 새 녹음 $_unlinkedRecordings개를 미연결로 보존했어요. 원하는 곡에 다시 연결해 주세요.';
  @override
  bool get automaticFollowupAllowed => !_authenticationBlocked;
  @override
  Future<List<SyncItem>> load() async {
    final result = <SyncItem>[];
    for (final mutation in await repository.pendingWork()) {
      var pendingReview = false;
      if (mutation.state == 'PENDING' && mutation.attemptCount == 0) {
        try {
          pendingReview = (await repository.review(mutation.opId))
              .pendingReview;
        } on StateError {
          // Ordinary pending work and unrelated holds are not reviewable.
        } on FormatException {
          // Unsupported metadata remains retained without an invented choice.
        }
      }
      result.add(
        SyncItem(
          mutation,
          await repository.retryStatus(mutation.opId),
          pendingReview: pendingReview,
        ),
      );
    }
    _unlinkedRecordings = await repository.unlinkedOfflineRecordingCount();
    return result;
  }

  @override
  Future<void> send() async {
    _authenticationBlocked = false;
    await repository.dispatch(
      transport: transport,
      session: session,
      limit: 50,
      onAuthenticationBlocked: () => _authenticationBlocked = true,
    );
    if (!_authenticationBlocked) {
      await uploads?.dispatch(
        onAuthenticationBlocked: () => _authenticationBlocked = true,
      );
    }
  }

  @override
  Future<bool> retry(String opId, int expectedAttempt) =>
      repository.retryMutation(opId, expectedAttempt: expectedAttempt);
  @override
  Future<DateTime?> nextAttempt() async {
    if (_authenticationBlocked) return null;
    final metadata = await repository.nextDispatchAt(),
        upload = await uploads?.nextAttempt();
    return metadata == null
        ? upload
        : upload == null
        ? metadata
        : metadata.isBefore(upload)
        ? metadata
        : upload;
  }
}

typedef SyncSchedule = VoidCallback Function(
  Duration delay,
  VoidCallback action,
);

/// One controller per account lease. It owns foreground timers, not background
/// execution. Store and transport fences remain the authority for account access.
final class SyncController extends ChangeNotifier {
  SyncController(
    this.backend, {
    this.conflicts,
    DateTime Function()? now,
    SyncSchedule? schedule,
  }) : _now = now ?? DateTime.now,
       _schedule = schedule ?? _timer;
  final SyncBackend backend;
  final ConflictActions? conflicts;
  String? get statusMessage => backend is SyncStatusSource
      ? (backend as SyncStatusSource).statusMessage
      : null;
  final DateTime Function() _now;
  final SyncSchedule _schedule;
  static VoidCallback _timer(Duration delay, VoidCallback action) {
    final timer = Timer(delay, action);
    return timer.cancel;
  }

  List<SyncItem> items = const [];
  List<CanonicalConflictReview> canonicalItems = const [];
  String? message;
  bool loaded = false;
  bool busy = false;
  bool _foreground = true, _enabled = false, _disposed = false;
  bool _wakeRequested = false;
  int _loadGeneration = 0, _timerGeneration = 0, _failures = 0;
  VoidCallback? _cancel;
  DateTime? _recoveryAt;
  bool get maySend => !_disposed && _foreground && _enabled;
  bool get needsResume => _failures >= 3;

  void _cancelTimer() {
    _timerGeneration++;
    _cancel?.call();
    _cancel = null;
  }

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    _cancelTimer();
    notifyListeners();
    if (maySend) unawaited(wake());
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _cancelTimer();
    notifyListeners();
    if (maySend) unawaited(wake());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final load = ++_loadGeneration;
    try {
      final next = await backend.load();
      final actions = conflicts;
      final candidates = actions is CanonicalConflictActions
          ? await (actions as CanonicalConflictActions).canonicalCandidates()
          : const <CanonicalConflictReview>[];
      if (_disposed || load != _loadGeneration) return;
      items = List.unmodifiable(next);
      canonicalItems = List.unmodifiable(candidates);
      loaded = true;
      message = null;
    } catch (_) {
      if (_disposed || load != _loadGeneration) return;
      message = '대기 정보를 확인하지 못했어요. 다시 확인해 주세요.';
    }
    notifyListeners();
  }

  Future<void> wake() async {
    if (!maySend) return;
    if (!busy && _failures > 0 && _failures < 3) {
      final remaining = _recoveryAt?.difference(_now().toUtc());
      if (remaining != null && remaining > Duration.zero) {
        _installTimer(remaining);
        return;
      }
    }
    await _run();
  }

  /// Explicit user action; lifecycle changes never reset internal failures.
  Future<void> resume() => _run(resetFailures: true);

  void _installTimer(Duration delay) {
    if (!maySend) return;
    _cancelTimer();
    final installed = _timerGeneration;
    _cancel = _schedule(delay, () {
      if (installed == _timerGeneration && maySend) unawaited(_run());
    });
  }

  Future<void> retry(SyncItem item) async {
    if (!maySend || busy || item.retry?.canRetryManually != true) return;
    await _run(manual: item, resetFailures: true);
  }

  Future<void> _run({SyncItem? manual, bool resetFailures = false}) async {
    // Authentication blocks survive a later lifecycle wake or scheduled timer,
    // not only the follow-up queued while the original request was in flight.
    // Explicit recovery remains distinct from these automatic triggers.
    if (!maySend || (!resetFailures && !backend.automaticFollowupAllowed)) {
      return;
    }
    if (busy) {
      _wakeRequested = true;
      return;
    }
    if (resetFailures) {
      _failures = 0;
      _recoveryAt = null;
    } else if (_failures >= 3) {
      return;
    }
    _wakeRequested = false;
    busy = true;
    _cancelTimer();
    notifyListeners();
    String? failureMessage;
    var operationSucceeded = false;
    try {
      final accepted =
          manual == null ||
          await backend.retry(
            manual.mutation.opId,
            manual.mutation.attemptCount,
          );
      if (_disposed) return;
      if (accepted && maySend) await backend.send();
      if (_disposed) return;
      await refresh();
      operationSucceeded = true;
    } catch (_) {
      _failures++;
      if (!_disposed) {
        await refresh();
        failureMessage = '전송을 이어가지 못했어요. 연결과 로그인 상태를 확인해 주세요.';
      }
    } finally {
      if (!_disposed) {
        if (failureMessage != null) message = failureMessage;
        // Keep the operation lock until deadline lookup finishes. A resume
        // during this await requests one followup instead of racing timers.
        await _arm(operationSucceeded: operationSucceeded);
        if (!_disposed) {
          busy = false;
          notifyListeners();
          final followup =
              _wakeRequested &&
              maySend &&
              _failures == 0 &&
              backend.automaticFollowupAllowed;
          _wakeRequested = false;
          if (followup) {
            scheduleMicrotask(() => unawaited(wake()));
          }
        }
      }
    }
  }

  Future<void> _arm({required bool operationSucceeded}) async {
    if (_disposed) return;
    if (_failures >= 3) {
      _recoveryAt = null;
      message = '자동 확인을 잠시 멈췄어요. 연결과 로그인 상태를 확인한 뒤 다시 시도해 주세요.';
      return;
    }
    DateTime? due;
    try {
      due = await backend.nextAttempt();
      if (_disposed) return;
      if (operationSucceeded) _failures = 0;
    } catch (_) {
      if (_disposed) return;
      _failures++;
      if (_failures >= 3) {
        _recoveryAt = null;
        message = '자동 확인을 잠시 멈췄어요. 상태를 다시 확인해 주세요.';
        return;
      }
      due = null;
    }
    if (due == null && _failures == 0) {
      _recoveryAt = null;
      return;
    }
    // The operation lock covers this lookup. Lifecycle cancellation invalidates
    // timer callbacks, not this result. Preserve recovery even while inactive.
    final current = _now().toUtc();
    var delay = due?.difference(current) ?? Duration.zero;
    final minimum = _failures > 0
        ? const Duration(seconds: 30)
        : const Duration(seconds: 1);
    if (delay < minimum) delay = minimum;
    _recoveryAt = _failures > 0 ? current.add(delay) : null;
    _installTimer(delay);
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _wakeRequested = false;
    _recoveryAt = null;
    _cancelTimer();
    items = const [];
    super.dispose();
  }
}
