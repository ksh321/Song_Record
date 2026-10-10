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
  int get schemaVersion => 12;

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
      if (from < 1 || from > 11 || to != 12) {
        throw StateError('Unsupported local schema migration: $from -> $to');
      }
      if (from < 2) {
        await migrator.createTable(mutationWireRequests);
        await migrator.createTrigger(mutationWireRequestImmutable);
      }
      if (from < 3) {
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
      }
      if (from < 4) {
        await migrator.createTrigger(mutationRowidImmutable);
        await migrator.createTrigger(mutationHistoryNoReplace);
        await migrator.createTrigger(mutationOrderPositive);
        await migrator.createTrigger(mutationHistoryNoDelete);
        await migrator.createTable(songAliases);
        await migrator.createTable(mutationSupersessions);
        await migrator.createTable(canonicalEditIntents);
        await migrator.createTable(mutationMappingHolds);
        await migrator.createIndex(songAliasDestination);
        await migrator.createIndex(canonicalIntentTarget);
        await migrator.createIndex(mutationMappingActiveHolds);
        await migrator.createTrigger(songAliasValidInsert);
        await migrator.createTrigger(songAliasNoUpdate);
        await migrator.createTrigger(songAliasNoDelete);
        await migrator.createTrigger(mutationSupersessionValidInsert);
        await migrator.createTrigger(mutationSupersessionNoUpdate);
        await migrator.createTrigger(mutationSupersessionNoDelete);
        await migrator.createTrigger(supersededMutationNoClaim);
        await migrator.createTrigger(canonicalIntentEvidenceImmutable);
        await migrator.createTrigger(canonicalIntentNoDelete);
        await migrator.createTrigger(mappingHoldReleaseOnly);
        await migrator.createTrigger(mappingHoldNoDelete);
        await migrator.createTrigger(songAliasNoReplace);
        await migrator.createTrigger(mutationSupersessionNoReplace);
        await migrator.createTrigger(canonicalIntentNoReplace);
        await migrator.createTrigger(mappingHoldNoReplace);
      }
      if (from < 5) {
        await migrator.createTable(snapshotDownloads);
        await migrator.createTable(snapshotDownloadRows);
        await migrator.createTable(snapshotDownloadProgress);
        await migrator.createTable(snapshotBaseline);
        await migrator.createTrigger(snapshotDownloadIdentity);
        await migrator.createTrigger(snapshotDownloadNoReplace);
        await migrator.createTrigger(snapshotRowInsert);
        await migrator.createTrigger(snapshotRowNoUpdate);
        await migrator.createTrigger(snapshotRowDelete);
        await migrator.createTrigger(snapshotProgressInsert);
        await migrator.createTrigger(snapshotProgressUpdate);
        await migrator.createTrigger(snapshotBaselineInsert);
        await migrator.createTrigger(snapshotBaselineUpdate);
      }
      if (from < 6) {
        await migrator.createTable(mutationConflictResolutions);
        await migrator.createTrigger(conflictResolutionValidInsert);
        await migrator.createTrigger(conflictResolutionNoReplace);
        await migrator.createTrigger(conflictResolutionNoUpdate);
        await migrator.createTrigger(conflictResolutionNoDelete);
        await migrator.createTrigger(resolvedMutationNoClaim);
      }
      if (from < 7) {
        await migrator.createTable(recordingFollowups);
        await migrator.createTrigger(recordingFollowupValidInsert);
        await migrator.createTrigger(recordingFollowupNoUpdate);
        await migrator.createTrigger(recordingFollowupNoDelete);
        await migrator.createTrigger(recordingFollowupNoReplace);
        await migrator.createTrigger(recordingFollowupOriginalNoClaim);
      } else if (from < 8) {
        // Only widen validated entity types. Existing v7 rows/wires stay intact.
        await customStatement('DROP TRIGGER recording_followup_valid_insert');
        await migrator.createTrigger(recordingFollowupValidInsert);
      }
      if (from == 6) {
        // Replace only the trigger definition; every history row stays intact.
        await customStatement('DROP TRIGGER conflict_resolution_valid_insert');
        await migrator.createTrigger(conflictResolutionValidInsert);
      }
      if (from < 11) {
        await migrator.createTable(localCleanupConfirmations);
        await migrator.createIndex(localCleanupRecording);
      }
      if (from < 10) {
        await migrator.createTable(localUploadQueue);
        await migrator.createIndex(localUploadReady);
        await migrator.createTrigger(localUploadIdentity);
      }
      if (from < 9) {
        await migrator.createTable(pendingEditResolutions);
        await migrator.createTrigger(pendingEditValidInsert);
        await migrator.createTrigger(pendingEditNoReplace);
        await migrator.createTrigger(pendingEditNoUpdate);
        await migrator.createTrigger(pendingEditNoDelete);
        await migrator.createTrigger(pendingEditOriginalNoClaim);
      }
      if (from >= 2 && from < 12) {
        await transaction(() async {
          // Copy immutable envelopes byte-for-byte; widen only the method check.
          // A v1 upgrade creates the widened definition directly.
          await customStatement("""CREATE TABLE mutation_wire_requests_v12 (
            op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
            contract_version TEXT NOT NULL,
            http_method TEXT NOT NULL CHECK (http_method IN ('POST','PATCH','PUT')),
            relative_path TEXT NOT NULL,
            body_json TEXT NOT NULL CHECK (json_valid(body_json) AND json_type(body_json)='object'),
            wire_hash TEXT NOT NULL CHECK (length(wire_hash)=64 AND wire_hash NOT GLOB '*[^0-9a-f]*')
          )""");
          await customStatement(
            'INSERT INTO mutation_wire_requests_v12 SELECT * FROM mutation_wire_requests',
          );
          final referringTriggers = await customSelect(
            "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND instr(sql,'mutation_wire_requests')>0",
          ).get();
          for (final trigger in referringTriggers) {
            final name = trigger.read<String>('name').replaceAll('"', '""');
            await customStatement('DROP TRIGGER "$name"');
          }
          await customStatement('DROP TABLE mutation_wire_requests');
          await customStatement(
            'ALTER TABLE mutation_wire_requests_v12 RENAME TO mutation_wire_requests',
          );
          for (final trigger in referringTriggers) {
            await customStatement(trigger.read<String>('sql'));
          }
        });
      }
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
