-- P04-08, local schema v1. Every file has exactly one immutable account owner.
CREATE TABLE local_account (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  user_id TEXT NOT NULL UNIQUE CHECK (length(user_id) = 36),
  environment TEXT NOT NULL CHECK (environment IN ('dev', 'staging', 'prod')),
  created_at INTEGER NOT NULL
);

CREATE TABLE metadata_copies (
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('SONG','RECORDING','PLAYLIST','PLAYLIST_ITEM','TAG',
    'RECORDING_TAG','RECORDING_CONDITION','RECORDING_FILE_SPEC','RECORDING_ASSET',
    'SONG_CLOUD_SELECTION','PIN_SLOT','USER_ENTITLEMENT','DELETION_LEDGER')),
  entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
  server_revision INTEGER NOT NULL DEFAULT 0 CHECK (server_revision >= 0),
  server_payload TEXT CHECK (server_payload IS NULL OR (json_valid(server_payload) AND json_type(server_payload) = 'object')),
  local_payload TEXT CHECK (local_payload IS NULL OR (json_valid(local_payload) AND json_type(local_payload) = 'object')),
  tombstone INTEGER NOT NULL DEFAULT 0 CHECK (tombstone IN (0,1)),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (entity_type, entity_id),
  CHECK ((server_revision = 0 AND server_payload IS NULL) OR (server_revision > 0 AND server_payload IS NOT NULL)),
  CHECK (tombstone = 0 OR server_revision > 0)
);

CREATE TABLE local_mutations (
  op_id TEXT NOT NULL PRIMARY KEY CHECK (length(op_id) = 36),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('CREATE','PATCH','TRASH','RESTORE','PURGE')),
  base_revision INTEGER NOT NULL CHECK (base_revision >= 0),
  base_payload TEXT CHECK (base_payload IS NULL OR (json_valid(base_payload) AND json_type(base_payload) = 'object')),
  payload TEXT NOT NULL CHECK (json_valid(payload) AND json_type(payload) = 'object'),
  request_hash TEXT NOT NULL CHECK (length(request_hash) = 64 AND request_hash NOT GLOB '*[^0-9a-f]*'),
  queue_state TEXT NOT NULL DEFAULT 'PENDING' CHECK (queue_state IN ('PENDING','SENDING','RETRY','CONFLICT','ACKED','FAILED')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at INTEGER,
  server_response TEXT CHECK (server_response IS NULL OR (json_valid(server_response) AND json_type(server_response) = 'object')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (entity_type, entity_id) REFERENCES metadata_copies(entity_type, entity_id),
  CHECK ((base_revision = 0 AND base_payload IS NULL) OR (base_revision > 0 AND base_payload IS NOT NULL))
);
CREATE INDEX mutation_queue ON local_mutations(queue_state, next_attempt_at, created_at, op_id);
CREATE INDEX mutation_target ON local_mutations(entity_type, entity_id, created_at);

CREATE TABLE local_recording_files (
  recording_id TEXT NOT NULL PRIMARY KEY CHECK (length(recording_id) = 36),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  relative_path TEXT NOT NULL UNIQUE,
  sha256 TEXT CHECK (sha256 IS NULL OR (length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*')),
  size_bytes INTEGER CHECK (size_bytes IS NULL OR size_bytes BETWEEN 1 AND 6291456),
  local_state TEXT NOT NULL CHECK (local_state IN ('CAPTURING','INPUT_PENDING','SAVED','INTERRUPTED','CORRUPT','MISSING')),
  cleanup_fence INTEGER NOT NULL DEFAULT 0 CHECK (cleanup_fence >= 0),
  verified_at INTEGER,
  updated_at INTEGER NOT NULL,
  UNIQUE (user_id, recording_id),
  CHECK (relative_path = 'audio/' || recording_id || '.m4a' OR relative_path = 'pending/' || recording_id || '.m4a.part'),
  CHECK (local_state NOT IN ('INPUT_PENDING','SAVED') OR (sha256 IS NOT NULL AND size_bytes IS NOT NULL AND verified_at IS NOT NULL
    AND relative_path = 'audio/' || recording_id || '.m4a'))
);

CREATE TABLE recording_journals (
  recording_id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NOT NULL,
  operation_id TEXT NOT NULL UNIQUE CHECK (length(operation_id) = 36),
  pending_path TEXT NOT NULL,
  final_path TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('PREPARING','CAPTURING','FINALIZING','VERIFIED','COMMITTED','FAILED')),
  recovery_payload TEXT NOT NULL CHECK (json_valid(recovery_payload) AND json_type(recovery_payload) = 'object'),
  revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id, recording_id) REFERENCES local_recording_files(user_id, recording_id),
  CHECK (pending_path = 'pending/' || recording_id || '.m4a.part'),
  CHECK (final_path = 'audio/' || recording_id || '.m4a')
);

CREATE TABLE import_jobs (
  import_job_id TEXT NOT NULL PRIMARY KEY CHECK (length(import_job_id) = 36),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  source_user_id TEXT NOT NULL CHECK (source_user_id = user_id),
  archive_path TEXT NOT NULL,
  manifest_hash TEXT NOT NULL CHECK (length(manifest_hash) = 64 AND manifest_hash NOT GLOB '*[^0-9a-f]*'),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','RUNNING','PAUSED','COMPLETED','FAILED')),
  total_items INTEGER NOT NULL CHECK (total_items >= 0),
  completed_items INTEGER NOT NULL DEFAULT 0 CHECK (completed_items BETWEEN 0 AND total_items),
  error_code TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (archive_path = 'imports/' || import_job_id || '.zip'),
  CHECK (status <> 'COMPLETED' OR completed_items = total_items)
);

CREATE TABLE import_items (
  import_job_id TEXT NOT NULL REFERENCES import_jobs(import_job_id),
  ordinal INTEGER NOT NULL CHECK (ordinal > 0),
  resource_id TEXT NOT NULL CHECK (length(resource_id) = 36),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPLIED','SKIPPED','CONFLICT','FAILED')),
  result_payload TEXT CHECK (result_payload IS NULL OR (json_valid(result_payload) AND json_type(result_payload) = 'object')),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (import_job_id, ordinal)
);

CREATE TABLE sync_cursors (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  last_change_seq INTEGER CHECK (last_change_seq IS NULL OR last_change_seq >= 0),
  baseline_complete INTEGER NOT NULL DEFAULT 0 CHECK (baseline_complete IN (0,1)),
  snapshot_resume TEXT CHECK (snapshot_resume IS NULL OR (json_valid(snapshot_resume) AND json_type(snapshot_resume) = 'object')),
  updated_at INTEGER NOT NULL,
  CHECK (baseline_complete = 0 OR last_change_seq IS NOT NULL)
);

CREATE TRIGGER local_account_no_update BEFORE UPDATE ON local_account BEGIN
  SELECT RAISE(ABORT, 'Local database ownership is immutable');
END;
CREATE TRIGGER local_account_no_delete BEFORE DELETE ON local_account BEGIN
  SELECT RAISE(ABORT, 'Local database ownership cannot be removed');
END;
CREATE TRIGGER mutation_request_immutable BEFORE UPDATE ON local_mutations
WHEN NEW.op_id <> OLD.op_id OR NEW.user_id <> OLD.user_id OR NEW.entity_type <> OLD.entity_type
  OR NEW.entity_id <> OLD.entity_id OR NEW.operation <> OLD.operation OR NEW.base_revision <> OLD.base_revision
  OR NEW.base_payload IS NOT OLD.base_payload OR NEW.payload <> OLD.payload OR NEW.request_hash <> OLD.request_hash
  OR NEW.created_at <> OLD.created_at OR NEW.attempt_count < OLD.attempt_count
BEGIN
  SELECT RAISE(ABORT, 'Mutation identity and request must survive retries unchanged');
END;
CREATE TRIGGER cursor_no_rewind BEFORE UPDATE ON sync_cursors
WHEN NEW.user_id <> OLD.user_id OR (OLD.last_change_seq IS NOT NULL AND
  (NEW.last_change_seq IS NULL OR NEW.last_change_seq < OLD.last_change_seq))
BEGIN
  SELECT RAISE(ABORT, 'Do not discard an acknowledged cursor');
END;
