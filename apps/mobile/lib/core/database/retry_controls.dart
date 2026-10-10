import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/mutation_request.dart';
import '../sync/retry_policy.dart';
import 'account_database.dart';
import 'local_models.dart';
import 'mapping_eligibility.dart';

typedef RetryClock = DateTime Function();

final class RetryStatus {
  const RetryStatus({
    required this.opId,
    required this.queueState,
    required this.attemptCount,
    required this.automaticRetriesClaimed,
    required this.mode,
    required this.lastAttemptKind,
    required this.nextAttemptAt,
    this.mappingEligible = true,
  });

  final String opId;
  final String queueState;
  final int attemptCount;

  /// NULL: legacy retry history cannot establish a safe automatic budget.
  final int? automaticRetriesClaimed;

  /// INITIAL, AUTO, MANUAL_REQUIRED, MANUAL_READY, BLOCKED.
  final String mode;

  /// INITIAL, AUTO, MANUAL, UNKNOWN.
  final String lastAttemptKind;
  final DateTime? nextAttemptAt;

  /// A read-only mapping gate, independent of the persisted retry mode/budget.
  final bool mappingEligible;

  bool get canRetryManually =>
      mappingEligible &&
      queueState == 'RETRY' &&
      (mode == 'AUTO' || mode == 'MANUAL_REQUIRED' || mode == 'BLOCKED');

  bool eligible(DateTime now, {bool includeFutureAutomatic = false}) {
    if (!mappingEligible) return false;
    if (mode == 'INITIAL') {
      return queueState == 'PENDING' &&
          attemptCount == 0 &&
          automaticRetriesClaimed == 0;
    }
    if (queueState != 'RETRY') return false;
    if (mode == 'MANUAL_READY') return true;
    final used = automaticRetriesClaimed;
    return mode == 'AUTO' &&
        used != null &&
        used < 3 &&
        (lastAttemptKind == 'INITIAL' || lastAttemptKind == 'AUTO') &&
        nextAttemptAt != null &&
        (includeFutureAutomatic || !nextAttemptAt!.isAfter(now));
  }
}

/// Internal DB helper. Mutating methods other than recoverOpening require
/// the caller's transaction; AccountStore owns the active-account fence.
final class RetryControls {
  RetryControls(this.database, {RetryClock? clock})
    : _clock = clock ?? DateTime.now;

  final AccountDatabase database;
  final RetryClock _clock;
  static const _policy = RetryPolicy();

  DateTime get now => _clock().toUtc();
  int get nowMs => now.millisecondsSinceEpoch;

  static const _select = '''
    SELECT m.op_id,m.queue_state,m.attempt_count,m.next_attempt_at,
      c.automatic_retries_claimed,c.retry_mode,c.last_attempt_kind
    FROM local_mutations m
    JOIN mutation_retry_controls c ON c.op_id=m.op_id
  ''';

  RetryStatus _decode(QueryRow row, {bool mappingEligible = true}) {
    final due = row.readNullable<int>('next_attempt_at');
    return RetryStatus(
      mappingEligible: mappingEligible,
      opId: row.read<String>('op_id'),
      queueState: row.read<String>('queue_state'),
      attemptCount: row.read<int>('attempt_count'),
      automaticRetriesClaimed: row.readNullable<int>(
        'automatic_retries_claimed',
      ),
      mode: row.read<String>('retry_mode'),
      lastAttemptKind: row.read<String>('last_attempt_kind'),
      nextAttemptAt: due == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(due, isUtc: true),
    );
  }

  Future<RetryStatus?> status(String opId) async {
    final row = await database
        .customSelect('$_select WHERE m.op_id=?', variables: [Variable(opId)])
        .getSingleOrNull();
    if (row == null) return null;

    final mapping = await readMappingEligibility(database);
    return _decode(row, mappingEligible: mapping.allows(opId));
  }

  Future<int> _change(String sql, List<Object?> args) async {
    await database.customStatement(sql, args);
    return (await database
            .customSelect('SELECT changes() AS affected')
            .getSingle())
        .read<int>('affected');
  }

  /// Do not remove delayed/blocked parents from the planner's input.
  /// Only the projected state changes; persisted queue states remain intact.
  Future<DispatchSnapshot> forPlanner(
    DispatchSnapshot snapshot, {
    bool includeFutureAutomatic = false,
  }) async {
    final rows = await database.customSelect(_select).get();
    final controls = {
      for (final row in rows) row.read<String>('op_id'): _decode(row),
    };
    final at = now;
    final pending = <QueuedMutation>[];
    final frozenRetries = <String>{};
    for (final mutation in snapshot.pending) {
      final control = controls[mutation.opId];
      if (control == null) {
        throw StateError('Mutation retry control is missing');
      }
      final eligible =
          snapshot.mapping.allows(mutation.opId) &&
          control.eligible(at, includeFutureAutomatic: includeFutureAutomatic);
      if (eligible && mutation.attemptCount > 0) {
        final frozen = await database
            .customSelect(
              'SELECT * FROM mutation_wire_requests WHERE op_id=?',
              variables: [Variable(mutation.opId)],
            )
            .getSingleOrNull();
        if (frozen != null && _restoreFrozen(mutation, frozen) != null) {
          frozenRetries.add(mutation.opId);
        }
      }
      pending.add(
        _withState(
          mutation,
          eligible
              ? 'PENDING'
              : mutation.state == 'PENDING'
              ? 'RETRY'
              : mutation.state,
        ),
      );
    }
    return DispatchSnapshot(
      pending: pending,
      baselines: snapshot.baselines,
      frozenRetries: frozenRetries,
      mapping: snapshot.mapping,
    );
  }

  QueuedMutation _withState(QueuedMutation m, String state) => QueuedMutation(
    opId: m.opId,
    localOrder: m.localOrder,
    entity: m.entity,
    entityId: m.entityId,
    operation: m.operation,
    state: state,
    baseRevision: m.baseRevision,
    payload: m.payload,
    basePayload: m.basePayload,
    serverResponse: m.serverResponse,
    attemptCount: m.attemptCount,
  );

  /// Called once during a successfully fenced account opening, never by polling.
  Future<void> recoverOpening(void Function() requireOpening) =>
      database.transaction(() async {
        requireOpening();
        final rows = await database
            .customSelect("$_select WHERE m.queue_state='SENDING'")
            .get();
        final at = now;
        for (final row in rows) {
          final control = _decode(row);
          final decision = _decision(
            control,
            state: 'RETRY',
            code: 'INTERRUPTED_SEND',
            status: null,
            at: at,
          );
          final changed = await _change(
            '''
              UPDATE local_mutations
              SET queue_state='RETRY',updated_at=?
              WHERE op_id=? AND queue_state='SENDING' AND attempt_count=?
            ''',
            [at.millisecondsSinceEpoch, control.opId, control.attemptCount],
          );
          if (changed != 1) {
            throw StateError('Interrupted attempt changed during recovery');
          }
          await _saveDecision(control.opId, decision, at);
        }
        requireOpening();
      });

  /// CAS grants exactly one manual claim. It neither increments nor resets
  /// attempt_count or automatic_retries_claimed.
  Future<bool> authorizeManual(
    String opId, {
    required int expectedAttempt,
  }) async {
    if (expectedAttempt < 0) {
      throw ArgumentError.value(expectedAttempt, 'expectedAttempt');
    }
    final current = await status(opId);
    if (current == null ||
        current.attemptCount != expectedAttempt ||
        !current.canRetryManually) {
      return false;
    }
    final changed = await _change(
      '''
        UPDATE mutation_retry_controls SET retry_mode='MANUAL_READY'
        WHERE op_id=? AND retry_mode IN ('AUTO','MANUAL_REQUIRED','BLOCKED')
          AND EXISTS (
            SELECT 1 FROM local_mutations m
            WHERE m.op_id=mutation_retry_controls.op_id
              AND m.queue_state='RETRY' AND m.attempt_count=?
          )
      ''',
      [opId, expectedAttempt],
    );
    if (changed != 1) return false;
    await database.customStatement(
      '''
        UPDATE local_mutations SET next_attempt_at=NULL,updated_at=?
        WHERE op_id=?
      ''',
      [nowMs, opId],
    );
    return true;
  }

  /// The caller must already have obtained this candidate from the complete
  /// dependency plan, within the same transaction.
  Future<MutationRequest?> claim(QueuedMutation candidate) async {
    final control = await status(candidate.opId);
    if (control == null ||
        control.attemptCount != candidate.attemptCount ||
        !control.eligible(now)) {
      return null;
    }

    final frozen = await database
        .customSelect(
          'SELECT * FROM mutation_wire_requests WHERE op_id=?',
          variables: [Variable(candidate.opId)],
        )
        .getSingleOrNull();

    final MutationRequest? request;
    if (frozen != null) {
      request = _restoreFrozen(candidate, frozen);
    } else if (candidate.attemptCount == 0) {
      request = MutationRequest.prepare(candidate);
    } else {
      // An already attempted request cannot be reconstructed from today's
      // prepare() contract if its original wire representation is missing.
      request = null;
    }

    if (request == null) {
      if (frozen != null || candidate.attemptCount > 0) {
        await _saveDecision(
          candidate.opId,
          const RetryDecision(RetryMode.blocked, null),
          now,
        );
      }
      return null;
    }

    final kind = switch (control.mode) {
      'INITIAL' => 'INITIAL',
      'AUTO' => 'AUTO',
      'MANUAL_READY' => 'MANUAL',
      _ => throw StateError('Ineligible retry mode'),
    };

    final changed = await _change(
      '''
        UPDATE local_mutations
        SET queue_state='SENDING',attempt_count=attempt_count+1,
          next_attempt_at=NULL,updated_at=?
        WHERE op_id=? AND queue_state=? AND attempt_count=?
      ''',
      [nowMs, candidate.opId, control.queueState, control.attemptCount],
    );
    if (changed != 1) return null;

    // Consumption happens before transaction commit, regardless of whether
    // transport subsequently starts, fails, or loses its response.
    final budgetChanged = await _change(
      '''
        UPDATE mutation_retry_controls
        SET automatic_retries_claimed =
          CASE WHEN ?='AUTO' THEN automatic_retries_claimed+1
            ELSE automatic_retries_claimed END,
          last_attempt_kind=?
        WHERE op_id=? AND retry_mode=?
          AND (?<>'AUTO' OR automatic_retries_claimed BETWEEN 0 AND 2)
      ''',
      [kind, kind, candidate.opId, control.mode, kind],
    );
    if (budgetChanged != 1) {
      throw StateError('Retry budget changed during claim');
    }

    if (frozen == null) {
      await database.customStatement(
        '''
          INSERT INTO mutation_wire_requests(
            op_id,contract_version,http_method,relative_path,body_json,wire_hash
          ) VALUES(?,?,?,?,?,?)
        ''',
        [
          candidate.opId,
          MutationRequest.contract,
          request.method,
          request.path,
          request.body,
          request.hash,
        ],
      );
    }
    return request;
  }

  /// Decoder for the persisted metadata-v1 envelope, independent of prepare().
  /// Never canonicalize or replace the saved request body while restoring it.
  MutationRequest? _restoreFrozen(QueuedMutation m, QueryRow row) {
    if (row.read<String>('contract_version') != 'metadata-v1' ||
        MutationRequest.contract != 'metadata-v1') {
      return null;
    }
    final route = switch (m.entity) {
      LocalEntity.song => 'songs',
      LocalEntity.recording => 'recordings',
      LocalEntity.tag => 'tags',
      _ => null,
    };
    if (route == null ||
        !{LocalOperation.create, LocalOperation.patch}.contains(m.operation)) {
      return null;
    }

    final create = m.operation == LocalOperation.create;
    final method = row.read<String>('http_method');
    final path = row.read<String>('relative_path');
    final body = row.read<String>('body_json');
    final representative =
        !create && m.entity == LocalEntity.song && method == 'PUT';
    if (representative) {
      final Object? original;
      try {
        original = jsonDecode(m.payload);
      } on FormatException {
        return null;
      }
      if (original is! Map<String, dynamic> ||
          original.length != 2 ||
          !original.containsKey('representative_recording_id') ||
          original['base_revision'] != m.baseRevision ||
          m.baseRevision < 1 ||
          path != '/v1/songs/${m.entityId}/representative' ||
          body !=
              canonicalJson({
                'base_revision': m.baseRevision,
                'recording_id': original['representative_recording_id'],
              })) {
        return null;
      }
      final target = original['representative_recording_id'];
      if (target != null) {
        if (target is! String) return null;
        try {
          if (UuidValue(target).value != target) return null;
        } on FormatException {
          return null;
        }
      }
    } else if (method != (create ? 'POST' : 'PATCH') ||
        path != '/v1/$route${create ? '' : '/${m.entityId}'}' ||
        body != m.payload) {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> ||
        (create && decoded['id'] != m.entityId) ||
        (!create && decoded['base_revision'] != m.baseRevision) ||
        (decoded.containsKey('user_id') &&
            decoded['user_id'] != database.userId)) {
      return null;
    }

    final restored = MutationRequest(
      mutation: m,
      method: method,
      path: path,
      body: body,
      attempt: m.attemptCount + 1,
    );
    return restored.hash == row.read<String>('wire_hash') ? restored : null;
  }

  RetryDecision _decision(
    RetryStatus control, {
    required String state,
    required String code,
    required int? status,
    required DateTime at,
  }) {
    if (state != 'RETRY') {
      return const RetryDecision(RetryMode.blocked, null);
    }

    final used = control.automaticRetriesClaimed;
    if (used == null || control.lastAttemptKind == 'UNKNOWN') {
      return RetryDecision(
        _policy.automaticFailure(code, status)
            ? RetryMode.manualRequired
            : RetryMode.blocked,
        null,
      );
    }

    final kind = switch (control.lastAttemptKind) {
      'INITIAL' => AttemptKind.initial,
      'AUTO' => AttemptKind.automatic,
      'MANUAL' => AttemptKind.manual,
      _ => throw StateError('Invalid persisted attempt kind'),
    };
    return _policy.afterFailure(
      automaticRetriesClaimed: used,
      lastAttempt: kind,
      code: code,
      status: status,
      now: at,
    );
  }

  Future<void> afterFailure(
    String opId, {
    required String state,
    required String code,
    required int? status,
  }) async {
    final control = await this.status(opId);
    if (control == null) {
      throw StateError('Mutation retry control is missing');
    }
    final at = now;
    await _saveDecision(
      opId,
      _decision(control, state: state, code: code, status: status, at: at),
      at,
    );
  }

  Future<void> finish(String opId) =>
      _saveDecision(opId, const RetryDecision(RetryMode.blocked, null), now);

  Future<void> _saveDecision(
    String opId,
    RetryDecision decision,
    DateTime at,
  ) async {
    final mode = switch (decision.mode) {
      RetryMode.auto => 'AUTO',
      RetryMode.manualRequired => 'MANUAL_REQUIRED',
      RetryMode.manualReady => 'MANUAL_READY',
      RetryMode.blocked => 'BLOCKED',
    };
    final changed = await _change(
      'UPDATE mutation_retry_controls SET retry_mode=? WHERE op_id=?',
      [mode, opId],
    );
    if (changed != 1) {
      throw StateError('Mutation retry control is missing');
    }
    await database.customStatement(
      '''
        UPDATE local_mutations SET next_attempt_at=?,updated_at=?
        WHERE op_id=?
      ''',
      [
        decision.nextAttemptAt?.toUtc().millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
        opId,
      ],
    );
  }
}
