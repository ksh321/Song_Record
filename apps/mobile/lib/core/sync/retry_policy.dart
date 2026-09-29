enum RetryMode { auto, manualRequired, blocked, manualReady }

enum AttemptKind { initial, automatic, manual }

final class RetryDecision {
  const RetryDecision(this.mode, this.nextAttemptAt);
  final RetryMode mode;
  final DateTime? nextAttemptAt;
}

/// Three additional automatic sends. Manual retry never creates a fresh budget.
final class RetryPolicy {
  const RetryPolicy();
  static const delays = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  RetryDecision afterFailure({
    required int automaticRetriesClaimed,
    required AttemptKind lastAttempt,
    required String code,
    required int? status,
    required DateTime now,
  }) {
    if (automaticRetriesClaimed < 0 || automaticRetriesClaimed > 3) {
      throw ArgumentError('Invalid persisted automatic retry budget');
    }
    if (!automaticFailure(code, status)) {
      return const RetryDecision(RetryMode.blocked, null);
    }
    if (lastAttempt == AttemptKind.manual || automaticRetriesClaimed == 3) {
      return const RetryDecision(RetryMode.manualRequired, null);
    }
    return RetryDecision(
      RetryMode.auto,
      now.toUtc().add(delays[automaticRetriesClaimed]),
    );
  }

  bool automaticFailure(String code, int? status) {
    // HTTP client errors win over a contradictory transient code. Match whole
    // underscore-delimited families: PROFILE is not a FILE error.
    final parts = code.split('_').toSet();
    if (status != null && status >= 400 && status < 500 ||
        parts.intersection({
          'AUTH',
          'REAUTH',
          'UNAUTHORIZED',
          'FORBIDDEN',
          'QUOTA',
          'LIMIT',
          'FILE',
          'VALIDATION',
          'INVALID',
        }).isNotEmpty) {
      return false;
    }
    return {
              'NETWORK_UNAVAILABLE',
              'RESPONSE_LOST',
              'INTERRUPTED_SEND',
            }.contains(code) &&
            (status == null || status >= 200 && status < 300) ||
        status != null && status >= 500 && status <= 599;
  }
}
