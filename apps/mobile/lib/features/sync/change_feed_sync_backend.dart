import '../../core/sync/change_feed_receiver.dart';
import '../auth/auth_session.dart';
import 'sync_controller.dart';

/// Uses only SyncController's foreground scheduling. Each wake receives at most
/// one page before sending; it never starts its own timer or a queued request.
final class ChangeFeedSyncBackend implements SyncBackend, SyncStatusSource {
  ChangeFeedSyncBackend({
    required this.outgoing,
    required this.receiver,
    required this.session,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final SyncBackend outgoing;
  final ChangeFeedStepper receiver;
  final Future<AuthSession> Function() session;
  final DateTime Function() _now;
  bool _blocked = false;
  DateTime? _due;
  ChangeFeedStep? lastStep;

  @override
  bool get automaticFollowupAllowed =>
      !_blocked && outgoing.automaticFollowupAllowed;
  @override
  String? get statusMessage => switch (lastStep) {
    ChangeFeedStep.authenticationRequired => '변경 정보를 받으려면 다시 로그인해 주세요.',
    ChangeFeedStep.cursorExpired ||
    ChangeFeedStep.needsInitialSnapshot => '초기 정보를 다시 받아야 해요. 기존 입력은 보존돼요.',
    ChangeFeedStep.progressed => '변경 정보를 받고 있어요.',
    ChangeFeedStep.retryLater => '변경 정보를 받지 못했어요. 연결 상태를 확인해 주세요.',
    ChangeFeedStep.caughtUp =>
      outgoing is SyncStatusSource
          ? (outgoing as SyncStatusSource).statusMessage
          : null,
    null => '변경 정보를 확인하고 있어요.',
  };
  @override
  Future<List<SyncItem>> load() => outgoing.load();
  @override
  Future<bool> retry(String id, int attempt) => outgoing.retry(id, attempt);
  @override
  Future<void> send() async {
    if (_blocked || (_due != null && _now().toUtc().isBefore(_due!))) return;
    _due = null;
    final ChangeFeedStep result;
    try {
      result = await receiver.step(await session());
    } on AuthFailure catch (error) {
      if (error.status != 401 && error.status != 403) rethrow;
      _blocked = true;
      lastStep = ChangeFeedStep.authenticationRequired;
      return;
    }
    lastStep = result;
    switch (result) {
      case ChangeFeedStep.authenticationRequired:
      case ChangeFeedStep.cursorExpired:
      case ChangeFeedStep.needsInitialSnapshot:
        _blocked = true;
        return;
      case ChangeFeedStep.progressed:
        _due = _now().toUtc().add(const Duration(seconds: 1));
        return;
      case ChangeFeedStep.retryLater:
        throw const AuthFailure('변경 정보를 받지 못했어요. 연결 상태를 확인해 주세요.');
      case ChangeFeedStep.caughtUp:
        await outgoing.send();
    }
  }

  @override
  Future<DateTime?> nextAttempt() async {
    if (_blocked || !outgoing.automaticFollowupAllowed) return null;
    return _due ?? await outgoing.nextAttempt();
  }
}
