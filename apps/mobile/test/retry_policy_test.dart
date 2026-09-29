import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/retry_policy.dart';

void main() {
  const policy = RetryPolicy();
  final now = DateTime.utc(2026, 9, 29);
  test(
    'three additional automatic attempts use 1, 5, 15 minutes then stop',
    () {
      for (var claimed = 0; claimed <= 3; claimed++) {
        final result = policy.afterFailure(
          automaticRetriesClaimed: claimed,
          lastAttempt: claimed == 0
              ? AttemptKind.initial
              : AttemptKind.automatic,
          code: 'NETWORK_UNAVAILABLE',
          status: null,
          now: now,
        );
        expect(
          result.mode,
          claimed == 3 ? RetryMode.manualRequired : RetryMode.auto,
        );
        expect(
          result.nextAttemptAt,
          claimed == 3 ? null : now.add(RetryPolicy.delays[claimed]),
        );
      }
    },
  );
  test('manual failure does not renew automatic budget', () {
    expect(
      policy
          .afterFailure(
            automaticRetriesClaimed: 0,
            lastAttempt: AttemptKind.manual,
            code: 'HTTP_503',
            status: 503,
            now: now,
          )
          .mode,
      RetryMode.manualRequired,
    );
  });
  test(
    'auth quota file malformed and local failures never schedule automatically',
    () {
      for (final failure in [
        ('HTTP_401', 401),
        ('HTTP_403', 403),
        ('HTTP_429', 429),
        ('AUTH_PROVIDER_UNAVAILABLE', 503),
        ('STORAGE_LIMIT', 503),
        ('FILE_UNAVAILABLE', 503),
        ('RESPONSE_UNCONFIRMED', 200),
        ('LOCAL_DATABASE_FAILURE', 0),
        ('VALIDATION_FAILED', 400),
        ('VALIDATION_FAILED', 503),
        ('RESPONSE_LOST', 400),
        ('FILE_INVALID', 503),
        ('AUTH_INVALID_SESSION', 503),
        ('SOURCE_TOKEN_INVALID', 503),
      ]) {
        final result = policy.afterFailure(
          automaticRetriesClaimed: 0,
          lastAttempt: AttemptKind.initial,
          code: failure.$1,
          status: failure.$2,
          now: now,
        );
        expect(result.mode, RetryMode.blocked);
        expect(result.nextAttemptAt, isNull);
      }
    },
  );
  test('whole error families do not mistake PROFILE for FILE', () {
    expect(policy.automaticFailure('PROFILE_SERVICE_UNAVAILABLE', 503), isTrue);
    expect(policy.automaticFailure('RESPONSE_LOST', 200), isTrue);
    expect(policy.automaticFailure('RESPONSE_LOST', null), isTrue);
  });
  test(
    'a delayed run schedules from the observed failure rather than catching up',
    () {
      final late = now.add(const Duration(hours: 3));
      expect(
        policy
            .afterFailure(
              automaticRetriesClaimed: 1,
              lastAttempt: AttemptKind.automatic,
              code: 'HTTP_503',
              status: 503,
              now: late,
            )
            .nextAttemptAt,
        late.add(const Duration(minutes: 5)),
      );
    },
  );
}
