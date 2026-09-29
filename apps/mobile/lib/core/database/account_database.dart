import 'package:drift/drift.dart';

import '../../config/app_config.dart';
import '../domain/identifiers.dart';

part 'account_database.g.dart';

/// Low-level storage. UI/repositories must use an AccountStore lease instead.
@DriftDatabase(include: {'local_schema.drift'})
class AccountDatabase extends _$AccountDatabase {
  AccountDatabase(
    super.executor, {
    required String userId,
    required this.environment,
  }) : userId = UuidValue(userId).value;

  final String userId;
  final AppEnvironment environment;

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await customStatement(
        'INSERT INTO local_account(singleton,user_id,environment,created_at) VALUES(1,?,?,?)',
        [userId, environment.name, now],
      );
      await customStatement(
        'INSERT INTO sync_cursors(singleton,user_id,updated_at) VALUES(1,?,?)',
        [userId, now],
      );
    },
    // No destructive fallback. Every future version needs an explicit,
    // data-preserving migration and a checked-in schema snapshot.
    onUpgrade: (migrator, from, to) async {
      if (from < 1 || from > 2 || to != 3) {
        throw StateError('Unsupported local schema migration: $from -> $to');
      }
      if (from < 2) {
        await migrator.createTable(mutationWireRequests);
        await migrator.createTrigger(mutationWireRequestImmutable);
      }
      await migrator.createTable(mutationRetryControls);
      await migrator.createTrigger(mutationRetryBudgetMonotonic);
      await customStatement('''
        INSERT INTO mutation_retry_controls(
          op_id,automatic_retries_claimed,retry_mode,last_attempt_kind
        )
        SELECT op_id,
          CASE WHEN queue_state='PENDING' AND attempt_count=0
            THEN 0 ELSE NULL END,
          CASE
            WHEN queue_state='PENDING' AND attempt_count=0 THEN 'INITIAL'
            WHEN queue_state IN ('PENDING','RETRY','SENDING')
              THEN 'MANUAL_REQUIRED'
            ELSE 'BLOCKED'
          END,
          CASE WHEN queue_state='PENDING' AND attempt_count=0
            THEN 'INITIAL' ELSE 'UNKNOWN' END
        FROM local_mutations
      ''');
      // Previously attempted PENDING rows must not become fresh initial sends.
      await customStatement("""
        UPDATE local_mutations SET queue_state='RETRY'
        WHERE queue_state='PENDING' AND attempt_count>0
      """);
      await customStatement("""
        UPDATE local_mutations SET next_attempt_at=NULL
        WHERE queue_state IN ('PENDING','RETRY','SENDING')
      """);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      final owner = await customSelect(
        'SELECT user_id,environment FROM local_account WHERE singleton=1',
      ).getSingle();
      if (owner.read<String>('user_id') != userId ||
          owner.read<String>('environment') != environment.name) {
        throw StateError('Local database account/environment mismatch');
      }
      final foreignKeys = await customSelect('PRAGMA foreign_keys').getSingle();
      if (foreignKeys.read<int>('foreign_keys') != 1) {
        throw StateError('Local foreign key enforcement is required');
      }
    },
  );

  Future<void> verifyReady() async {
    await customSelect('SELECT 1').get();
  }
}
