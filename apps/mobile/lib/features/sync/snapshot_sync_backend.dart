import '../../core/sync/snapshot_receiver.dart';
import '../auth/auth_session.dart';
import 'sync_controller.dart';

/// Composes initial receiving with the existing foreground scheduler. No timer
/// or queued follow-up lives here; the controller remains the single scheduler.
final class SnapshotSyncBackend implements SyncBackend, SyncStatusSource {
  SnapshotSyncBackend({
    required this.outgoing,
    required this.receiver,
    required this.session,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final SyncBackend outgoing;
  final SnapshotStepper receiver;
  final Future<AuthSession> Function() session;
  final DateTime Function() _now;
  bool _complete = false, _authBlocked = false;
  DateTime? _due;
  SnapshotStep? lastStep;

  @override
  String? get statusMessage {
    if (_authBlocked) return '초기 정보를 받으려면 다시 로그인해 주세요.';
    if (_complete) {
      return outgoing is SyncStatusSource
          ? (outgoing as SyncStatusSource).statusMessage
          : null;
    }
    return switch (lastStep) {
      SnapshotStep.waiting => '서버에서 초기 정보를 준비하고 있어요.',
      SnapshotStep.retryLater => '초기 정보를 받지 못했어요. 연결 상태를 확인해 주세요.',
      _ => '초기 정보를 받고 있어요. 기존 입력은 보존돼요.',
    };
  }

  @override
  bool get automaticFollowupAllowed =>
      !_authBlocked && outgoing.automaticFollowupAllowed;
  @override
  Future<List<SyncItem>> load() => outgoing.load();
  @override
  Future<bool> retry(String opId, int expectedAttempt) =>
      outgoing.retry(opId, expectedAttempt);
  @override
  Future<void> send() async {
    if (_authBlocked) return;
    if (!_complete) {
      if (_due != null && _now().toUtc().isBefore(_due!)) return;
      _due = null;
      final SnapshotStep result;
      try {
        result = await receiver.step(await session());
      } on AuthFailure catch (error) {
        if (error.status != 401 && error.status != 403) rethrow;
        _authBlocked = true;
        lastStep = SnapshotStep.authenticationRequired;
        return;
      }
      lastStep = result;
      switch (result) {
        case SnapshotStep.complete:
          _complete = true;
        case SnapshotStep.authenticationRequired:
          _authBlocked = true;
          return;
        case SnapshotStep.progressed:
          _due = _now().toUtc().add(const Duration(seconds: 1));
          return;
        case SnapshotStep.waiting:
          _due = _now().toUtc().add(const Duration(seconds: 5));
          return;
        case SnapshotStep.retryLater:
          throw const AuthFailure('초기 정보를 받지 못했어요. 연결 상태를 확인해 주세요.');
      }
    }
    await outgoing.send();
  }

  @override
  Future<DateTime?> nextAttempt() async {
    if (_authBlocked) return null;
    return _complete ? outgoing.nextAttempt() : _due;
  }
}
