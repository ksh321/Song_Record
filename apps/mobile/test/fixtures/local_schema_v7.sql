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

-- P10-02b: freeze the HTTP contract independently of the local edit fingerprint.
-- P10-02: preserve offline PATCH intent while materializing an acknowledged baseline.
CREATE TABLE recording_followups (
  original_op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
  replacement_op_id TEXT NOT NULL UNIQUE REFERENCES local_mutations(op_id),
  predecessor_op_id TEXT NOT NULL REFERENCES local_mutations(op_id),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  logical_order INTEGER NOT NULL CHECK(logical_order > 0),
  created_at INTEGER NOT NULL,
  CHECK(original_op_id <> replacement_op_id),
  CHECK(original_op_id <> predecessor_op_id),
  CHECK(replacement_op_id <> predecessor_op_id)
) WITHOUT ROWID;

CREATE TRIGGER recording_followup_valid_insert BEFORE INSERT ON recording_followups BEGIN
  SELECT RAISE(ABORT, 'Invalid recording followup') WHERE NOT EXISTS (
    SELECT 1 FROM local_mutations o JOIN local_mutations r ON r.op_id=NEW.replacement_op_id
    JOIN local_mutations p ON p.op_id=NEW.predecessor_op_id
    WHERE o.op_id=NEW.original_op_id AND o.user_id=NEW.user_id
      AND r.user_id=o.user_id AND p.user_id=o.user_id
      AND o.entity_type='RECORDING' AND r.entity_type=o.entity_type AND p.entity_type=o.entity_type
      AND r.entity_id=o.entity_id AND p.entity_id=o.entity_id
      AND o.operation='PATCH' AND r.operation='PATCH'
      AND o.base_revision=0 AND o.attempt_count=0 AND o.queue_state='PENDING'
      AND r.base_revision>0 AND r.attempt_count=0 AND r.queue_state='PENDING'
      AND p.queue_state='ACKED' AND p.attempt_count>0
      AND NEW.logical_order=o.rowid AND r.rowid>o.rowid
      AND json_extract(p.server_response,'$.revision')=r.base_revision
  );
END;
CREATE TRIGGER recording_followup_no_update BEFORE UPDATE ON recording_followups BEGIN
  SELECT RAISE(ABORT, 'Recording followup evidence is immutable');
END;
CREATE TRIGGER recording_followup_no_delete BEFORE DELETE ON recording_followups BEGIN
  SELECT RAISE(ABORT, 'Recording followup evidence must be retained');
END;
CREATE TRIGGER recording_followup_no_replace BEFORE INSERT ON recording_followups BEGIN
  SELECT RAISE(ABORT, 'Recording followup evidence cannot be replaced') WHERE EXISTS (
    SELECT 1 FROM recording_followups WHERE original_op_id=NEW.original_op_id OR replacement_op_id=NEW.replacement_op_id
  );
END;
CREATE TRIGGER recording_followup_original_no_claim BEFORE UPDATE OF attempt_count ON local_mutations
WHEN NEW.attempt_count>OLD.attempt_count AND EXISTS (
  SELECT 1 FROM recording_followups WHERE original_op_id=OLD.op_id
) BEGIN
  SELECT RAISE(ABORT, 'Original offline intent cannot be sent after materialization');
END;

CREATE TABLE mutation_wire_requests (
  op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
  contract_version TEXT NOT NULL,
  http_method TEXT NOT NULL CHECK (http_method IN ('POST','PATCH')),
  relative_path TEXT NOT NULL,
  body_json TEXT NOT NULL CHECK (json_valid(body_json) AND json_type(body_json)='object'),
  wire_hash TEXT NOT NULL CHECK (length(wire_hash)=64 AND wire_hash NOT GLOB '*[^0-9a-f]*')
);
CREATE TRIGGER mutation_wire_request_immutable BEFORE UPDATE ON mutation_wire_requests BEGIN
  SELECT RAISE(ABORT, 'Frozen HTTP requests must survive retries unchanged');
END;

-- P10-03: NULL budget means legacy history is unknown.
CREATE TABLE mutation_retry_controls (
  op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
  automatic_retries_claimed INTEGER
    CHECK (automatic_retries_claimed IS NULL
      OR automatic_retries_claimed BETWEEN 0 AND 3),
  retry_mode TEXT NOT NULL CHECK (
    retry_mode IN ('INITIAL','AUTO','MANUAL_REQUIRED','MANUAL_READY','BLOCKED')
  ),
  last_attempt_kind TEXT NOT NULL CHECK (
    last_attempt_kind IN ('INITIAL','AUTO','MANUAL','UNKNOWN')
  )
);

CREATE TRIGGER mutation_retry_budget_monotonic
BEFORE UPDATE ON mutation_retry_controls
WHEN NEW.op_id <> OLD.op_id
  OR (OLD.automatic_retries_claimed IS NULL
      AND NEW.automatic_retries_claimed IS NOT NULL)
  OR (OLD.automatic_retries_claimed IS NOT NULL
      AND NEW.automatic_retries_claimed IS NULL)
  OR NEW.automatic_retries_claimed < OLD.automatic_retries_claimed
  OR NEW.automatic_retries_claimed > OLD.automatic_retries_claimed + 1
BEGIN
  SELECT RAISE(ABORT, 'Automatic retry budget cannot be replenished');
END;

-- P10-04: additive schema v4.

CREATE TABLE song_aliases (
  source_song_id TEXT NOT NULL PRIMARY KEY,
  canonical_song_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  entity_type TEXT NOT NULL DEFAULT 'SONG' CHECK (entity_type = 'SONG'),
  mapping_op_id TEXT NOT NULL UNIQUE REFERENCES local_mutations(op_id),
  receipt_status INTEGER NOT NULL CHECK (receipt_status = 200),
  receipt_body TEXT NOT NULL
    CHECK (json_valid(receipt_body) AND json_type(receipt_body) = 'object'),
  created_at INTEGER NOT NULL,
  FOREIGN KEY (entity_type, source_song_id)
    REFERENCES metadata_copies(entity_type, entity_id),
  FOREIGN KEY (entity_type, canonical_song_id)
    REFERENCES metadata_copies(entity_type, entity_id),
  CHECK (source_song_id <> canonical_song_id),
  CHECK (json_type(receipt_body, '$.created') IS 'false'),
  CHECK (json_type(receipt_body, '$.song') IS 'object'),
  CHECK (
    json_extract(receipt_body, '$.canonical_song_id')
      IS canonical_song_id
  ),
  CHECK (
    json_extract(receipt_body, '$.song.id')
      IS canonical_song_id
  ),
  CHECK (
    json_type(receipt_body, '$.song.revision') IS 'integer'
    AND json_extract(receipt_body, '$.song.revision') > 0
  ),
  CHECK (
    json_extract(receipt_body, '$.song.lifecycle_state') IS 'ACTIVE'
  )
) WITHOUT ROWID;

CREATE INDEX song_alias_destination
  ON song_aliases(canonical_song_id);

CREATE TABLE mutation_supersessions (
  original_op_id TEXT NOT NULL PRIMARY KEY
    REFERENCES local_mutations(op_id),
  replacement_op_id TEXT NOT NULL UNIQUE
    REFERENCES local_mutations(op_id),
  mapping_source_id TEXT NOT NULL REFERENCES song_aliases(source_song_id),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  order_root_op_id TEXT NOT NULL REFERENCES local_mutations(op_id),
  logical_order INTEGER NOT NULL CHECK (logical_order > 0),
  created_at INTEGER NOT NULL,
  CHECK (original_op_id <> replacement_op_id)
) WITHOUT ROWID;

CREATE TABLE canonical_edit_intents (
  intent_id TEXT NOT NULL PRIMARY KEY CHECK (length(intent_id) = 36),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  mapping_source_id TEXT NOT NULL REFERENCES song_aliases(source_song_id),
  intent_key TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (
    kind IN ('SONG_VALUES', 'SONG_MUTATION', 'REFERENCE_RELINK')
  ),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  origin_op_id TEXT REFERENCES local_mutations(op_id),
  evidence_json TEXT NOT NULL
    CHECK (json_valid(evidence_json) AND json_type(evidence_json) = 'object'),
  state TEXT NOT NULL DEFAULT 'OPEN'
    CHECK (state IN ('OPEN', 'QUEUED', 'RESOLVED')),
  resolution_json TEXT
    CHECK (
      resolution_json IS NULL OR
      (json_valid(resolution_json) AND json_type(resolution_json) = 'object')
    ),
  resolution_op_id TEXT REFERENCES local_mutations(op_id),
  resolved_at INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (entity_type, entity_id)
    REFERENCES metadata_copies(entity_type, entity_id),
  UNIQUE (mapping_source_id, intent_key),
  CHECK (
    (state = 'OPEN'
      AND resolution_json IS NULL
      AND resolution_op_id IS NULL
      AND resolved_at IS NULL)
    OR
    (state = 'QUEUED'
      AND resolution_json IS NOT NULL
      AND resolution_op_id IS NOT NULL
      AND resolved_at IS NULL)
    OR
    (state = 'RESOLVED'
      AND resolution_json IS NOT NULL
      AND resolved_at IS NOT NULL)
  )
) WITHOUT ROWID;

CREATE INDEX canonical_intent_target
  ON canonical_edit_intents(entity_type, entity_id, state);

CREATE TABLE mutation_mapping_holds (
  op_id TEXT NOT NULL REFERENCES local_mutations(op_id),
  mapping_source_id TEXT NOT NULL REFERENCES song_aliases(source_song_id),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  reason TEXT NOT NULL CHECK (length(reason) BETWEEN 1 AND 64),
  disposition TEXT NOT NULL CHECK (
    disposition IN ('BLOCK', 'REPLAY_ORIGINAL')
  ),
  intent_id TEXT REFERENCES canonical_edit_intents(intent_id),
  created_at INTEGER NOT NULL,
  released_at INTEGER,
  release_evidence TEXT
    CHECK (
      release_evidence IS NULL OR
      (json_valid(release_evidence) AND json_type(release_evidence) = 'object')
    ),
  PRIMARY KEY (op_id, mapping_source_id, reason),
  CHECK (
    (released_at IS NULL AND release_evidence IS NULL)
    OR
    (released_at IS NOT NULL AND release_evidence IS NOT NULL)
  )
) WITHOUT ROWID;

CREATE INDEX mutation_mapping_active_holds
  ON mutation_mapping_holds(op_id, released_at);

CREATE TRIGGER song_alias_valid_insert
BEFORE INSERT ON song_aliases BEGIN
  SELECT RAISE(ABORT, 'Alias requires its original song CREATE')
  WHERE NOT EXISTS (
    SELECT 1 FROM local_mutations m
    WHERE m.op_id = NEW.mapping_op_id
      AND m.user_id = NEW.user_id
      AND m.entity_type = 'SONG'
      AND m.entity_id = NEW.source_song_id
      AND m.operation = 'CREATE'
  );

  SELECT RAISE(ABORT, 'Song alias cycle')
  WHERE EXISTS (
    WITH RECURSIVE destinations(id) AS (
      SELECT NEW.canonical_song_id
      UNION
      SELECT a.canonical_song_id
      FROM song_aliases a
      JOIN destinations d ON a.source_song_id = d.id
    )
    SELECT 1 FROM destinations WHERE id = NEW.source_song_id
  );
END;

CREATE TRIGGER song_alias_no_update
BEFORE UPDATE ON song_aliases BEGIN
  SELECT RAISE(ABORT, 'Song aliases and receipts are immutable');
END;

CREATE TRIGGER song_alias_no_delete
BEFORE DELETE ON song_aliases BEGIN
  SELECT RAISE(ABORT, 'Song alias evidence must be retained');
END;

CREATE TRIGGER mutation_supersession_valid_insert
BEFORE INSERT ON mutation_supersessions BEGIN
  SELECT RAISE(ABORT, 'Cannot prepend a frozen replacement chain')
  WHERE EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = NEW.replacement_op_id);

  -- A replacement is a newly appended mutation. This also prevents cycles.
  SELECT RAISE(ABORT, 'Invalid replacement order')
  WHERE NOT EXISTS (
    SELECT 1
    FROM local_mutations original
    JOIN local_mutations replacement
      ON replacement.op_id = NEW.replacement_op_id
    WHERE original.op_id = NEW.original_op_id
      AND replacement.rowid > original.rowid
  );

  SELECT RAISE(ABORT, 'Replacement must inherit original logical order')
  WHERE NEW.order_root_op_id IS NOT COALESCE(
    (SELECT order_root_op_id FROM mutation_supersessions
      WHERE replacement_op_id = NEW.original_op_id),
    NEW.original_op_id
  ) OR NEW.logical_order IS NOT COALESCE(
    (SELECT logical_order FROM mutation_supersessions
      WHERE replacement_op_id = NEW.original_op_id),
    (SELECT rowid FROM local_mutations
      WHERE op_id = NEW.original_op_id)
  );
END;

CREATE TRIGGER mutation_supersession_no_update
BEFORE UPDATE ON mutation_supersessions BEGIN
  SELECT RAISE(ABORT, 'Mutation supersessions are immutable');
END;

CREATE TRIGGER mutation_supersession_no_delete
BEFORE DELETE ON mutation_supersessions BEGIN
  SELECT RAISE(ABORT, 'Mutation supersession history must be retained');
END;

CREATE TRIGGER superseded_mutation_no_claim
BEFORE UPDATE OF attempt_count ON local_mutations
WHEN NEW.attempt_count > OLD.attempt_count
  AND EXISTS (
    SELECT 1 FROM mutation_supersessions
    WHERE original_op_id = OLD.op_id
  )
BEGIN
  SELECT RAISE(ABORT, 'Superseded mutation cannot be claimed');
END;

CREATE TRIGGER canonical_intent_evidence_immutable
BEFORE UPDATE ON canonical_edit_intents
WHEN NEW.intent_id IS NOT OLD.intent_id
  OR NEW.user_id IS NOT OLD.user_id
  OR NEW.mapping_source_id IS NOT OLD.mapping_source_id
  OR NEW.intent_key IS NOT OLD.intent_key
  OR NEW.kind IS NOT OLD.kind
  OR NEW.entity_type IS NOT OLD.entity_type
  OR NEW.entity_id IS NOT OLD.entity_id
  OR NEW.origin_op_id IS NOT OLD.origin_op_id
  OR NEW.evidence_json IS NOT OLD.evidence_json
  OR NEW.created_at IS NOT OLD.created_at
  OR OLD.state = 'RESOLVED'
  OR (OLD.state = 'QUEUED' AND NEW.state <> 'RESOLVED')
BEGIN
  SELECT RAISE(ABORT, 'Canonical intent evidence cannot be rewritten');
END;

CREATE TRIGGER canonical_intent_no_delete
BEFORE DELETE ON canonical_edit_intents BEGIN
  SELECT RAISE(ABORT, 'Canonical edit evidence must be retained');
END;

CREATE TRIGGER mapping_hold_release_only
BEFORE UPDATE ON mutation_mapping_holds
WHEN NEW.op_id IS NOT OLD.op_id
  OR NEW.mapping_source_id IS NOT OLD.mapping_source_id
  OR NEW.user_id IS NOT OLD.user_id
  OR NEW.reason IS NOT OLD.reason
  OR NEW.disposition IS NOT OLD.disposition
  OR NEW.intent_id IS NOT OLD.intent_id
  OR NEW.created_at IS NOT OLD.created_at
  OR OLD.released_at IS NOT NULL
  OR NEW.released_at IS NULL
BEGIN
  SELECT RAISE(ABORT, 'Mapping hold permits one evidenced release only');
END;

CREATE TRIGGER mapping_hold_no_delete
BEFORE DELETE ON mutation_mapping_holds BEGIN
  SELECT RAISE(ABORT, 'Mapping hold history must be retained');
END;

CREATE TRIGGER song_alias_no_replace BEFORE INSERT ON song_aliases BEGIN
  SELECT RAISE(ABORT, 'Preserved evidence cannot be replaced')
  WHERE EXISTS (SELECT 1 FROM song_aliases WHERE source_song_id = NEW.source_song_id OR mapping_op_id = NEW.mapping_op_id);
END;

CREATE TRIGGER mutation_supersession_no_replace BEFORE INSERT ON mutation_supersessions BEGIN
  SELECT RAISE(ABORT, 'Preserved evidence cannot be replaced')
  WHERE EXISTS (SELECT 1 FROM mutation_supersessions WHERE original_op_id = NEW.original_op_id OR replacement_op_id = NEW.replacement_op_id);
END;

CREATE TRIGGER canonical_intent_no_replace BEFORE INSERT ON canonical_edit_intents BEGIN
  SELECT RAISE(ABORT, 'Preserved evidence cannot be replaced')
  WHERE EXISTS (SELECT 1 FROM canonical_edit_intents WHERE intent_id = NEW.intent_id OR (mapping_source_id = NEW.mapping_source_id AND intent_key = NEW.intent_key));
END;

CREATE TRIGGER mapping_hold_no_replace BEFORE INSERT ON mutation_mapping_holds BEGIN
  SELECT RAISE(ABORT, 'Preserved evidence cannot be replaced')
  WHERE EXISTS (SELECT 1 FROM mutation_mapping_holds WHERE op_id = NEW.op_id AND mapping_source_id = NEW.mapping_source_id AND reason = NEW.reason);
END;

CREATE TRIGGER mutation_rowid_immutable BEFORE UPDATE ON local_mutations
WHEN NEW.rowid IS NOT OLD.rowid BEGIN
  SELECT RAISE(ABORT, 'Mutation rowid must remain immutable');
END;
CREATE TRIGGER mutation_history_no_replace BEFORE INSERT ON local_mutations
WHEN EXISTS (SELECT 1 FROM local_mutations
  WHERE op_id = NEW.op_id OR (NEW.rowid <> -1 AND rowid = NEW.rowid)) BEGIN
  SELECT RAISE(ABORT, 'Mutation history cannot be replaced');
END;
CREATE TRIGGER mutation_order_positive AFTER INSERT ON local_mutations
WHEN NEW.rowid <= 0 BEGIN
  SELECT RAISE(ABORT, 'New mutation order must be positive');
END;
CREATE TRIGGER mutation_history_no_delete BEFORE DELETE ON local_mutations BEGIN
  SELECT RAISE(ABORT, 'Mutation ordering history must be retained');
END;

-- P10-05: separate durable download area. No source/queue/audio tables are replaced.
CREATE TABLE snapshot_downloads (
  snapshot_token TEXT NOT NULL PRIMARY KEY CHECK (length(snapshot_token)=36),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  manifest_json TEXT NOT NULL CHECK (json_valid(manifest_json) AND json_type(manifest_json)='object'),
  snapshot_cursor INTEGER NOT NULL CHECK (snapshot_cursor>=0),
  expires_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'RECEIVING' CHECK (state IN ('RECEIVING','VERIFIED','APPLIED')),
  created_at INTEGER NOT NULL,
  UNIQUE(snapshot_token,user_id),
  CHECK (json_extract(manifest_json,'$.snapshot_token') IS snapshot_token),
  CHECK (json_extract(manifest_json,'$.snapshot_cursor') IS snapshot_cursor)
);

CREATE TABLE snapshot_download_rows (
  snapshot_token TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  entity TEXT NOT NULL CHECK (entity IN ('SONG','SONG_SOURCE','RECORDING','RECORDING_FILE_SPEC','RECORDING_ASSET',
    'PLAYLIST','PLAYLIST_ITEM','TAG','RECORDING_TAG','RECORDING_CONDITION','USER_ENTITLEMENT','STORAGE_USAGE',
    'SONG_CLOUD_SELECTION','PIN_SLOT','USER_SYNC_STATE','CHANGE_LOG','DELETION_BATCH','DELETION_ITEM','DELETION_LEDGER')),
  ordinal INTEGER NOT NULL CHECK (ordinal>0),
  resource_id TEXT NOT NULL CHECK (length(resource_id)=36),
  canonical_payload TEXT NOT NULL CHECK (json_valid(canonical_payload) AND json_type(canonical_payload)='object'),
  PRIMARY KEY(snapshot_token,entity,ordinal),
  FOREIGN KEY(snapshot_token,user_id) REFERENCES snapshot_downloads(snapshot_token,user_id) ON DELETE CASCADE,
  CHECK (json_extract(canonical_payload,'$.user_id') IS user_id)
);

CREATE TABLE snapshot_download_progress (
  snapshot_token TEXT NOT NULL REFERENCES snapshot_downloads(snapshot_token) ON DELETE CASCADE,
  entity TEXT NOT NULL CHECK (entity IN ('SONG','SONG_SOURCE','RECORDING','RECORDING_FILE_SPEC','RECORDING_ASSET',
    'PLAYLIST','PLAYLIST_ITEM','TAG','RECORDING_TAG','RECORDING_CONDITION','USER_ENTITLEMENT','STORAGE_USAGE',
    'SONG_CLOUD_SELECTION','PIN_SLOT','USER_SYNC_STATE','CHANGE_LOG','DELETION_BATCH','DELETION_ITEM','DELETION_LEDGER')),
  last_ordinal INTEGER NOT NULL CHECK (last_ordinal>=0),
  next_cursor TEXT,
  finished INTEGER NOT NULL CHECK (finished IN (0,1)),
  PRIMARY KEY(snapshot_token,entity),
  CHECK ((finished=1 AND next_cursor IS NULL) OR (finished=0 AND next_cursor IS NOT NULL AND next_cursor LIKE 'sp1.%' AND last_ordinal>0))
);

CREATE TABLE snapshot_baseline (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton=1),
  snapshot_token TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  FOREIGN KEY(snapshot_token,user_id) REFERENCES snapshot_downloads(snapshot_token,user_id)
);

CREATE TRIGGER snapshot_download_identity BEFORE UPDATE ON snapshot_downloads
WHEN NEW.snapshot_token IS NOT OLD.snapshot_token OR NEW.user_id IS NOT OLD.user_id
  OR NEW.manifest_json IS NOT OLD.manifest_json OR NEW.snapshot_cursor IS NOT OLD.snapshot_cursor
  OR NEW.expires_at IS NOT OLD.expires_at OR NEW.created_at IS NOT OLD.created_at
  OR NOT ((OLD.state='RECEIVING' AND NEW.state='VERIFIED') OR (OLD.state='VERIFIED' AND NEW.state='APPLIED'))
BEGIN SELECT RAISE(ABORT,'Snapshot manifest and forward state are immutable'); END;

CREATE TRIGGER snapshot_download_no_replace BEFORE INSERT ON snapshot_downloads
WHEN NEW.state<>'RECEIVING' OR EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token)
BEGIN SELECT RAISE(ABORT,'Snapshot manifest cannot be replaced'); END;

CREATE TRIGGER snapshot_row_insert BEFORE INSERT ON snapshot_download_rows
WHEN NOT EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token AND user_id=NEW.user_id AND state='RECEIVING')
 OR EXISTS(SELECT 1 FROM snapshot_download_rows WHERE snapshot_token=NEW.snapshot_token AND entity=NEW.entity AND ordinal=NEW.ordinal)
BEGIN SELECT RAISE(ABORT,'Only new receiving snapshot rows may be inserted'); END;

CREATE TRIGGER snapshot_row_no_update BEFORE UPDATE ON snapshot_download_rows
BEGIN SELECT RAISE(ABORT,'Snapshot rows are immutable'); END;

CREATE TRIGGER snapshot_row_delete BEFORE DELETE ON snapshot_download_rows
WHEN EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=OLD.snapshot_token AND state<>'RECEIVING')
BEGIN SELECT RAISE(ABORT,'Verified snapshot rows must remain intact'); END;

CREATE TRIGGER snapshot_progress_insert BEFORE INSERT ON snapshot_download_progress
WHEN NOT EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token AND state='RECEIVING')
 OR EXISTS(SELECT 1 FROM snapshot_download_progress WHERE snapshot_token=NEW.snapshot_token AND entity=NEW.entity)
BEGIN SELECT RAISE(ABORT,'Snapshot progress cannot be replaced'); END;

CREATE TRIGGER snapshot_progress_update BEFORE UPDATE ON snapshot_download_progress
WHEN NEW.snapshot_token IS NOT OLD.snapshot_token OR NEW.entity IS NOT OLD.entity
 OR OLD.finished=1 OR NEW.last_ordinal<=OLD.last_ordinal
 OR NOT EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token AND state='RECEIVING')
BEGIN SELECT RAISE(ABORT,'Snapshot progress must advance while receiving'); END;

CREATE TRIGGER snapshot_baseline_insert BEFORE INSERT ON snapshot_baseline
WHEN NOT EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token AND user_id=NEW.user_id AND state='APPLIED')
BEGIN SELECT RAISE(ABORT,'Only an applied snapshot may become baseline'); END;

CREATE TRIGGER snapshot_baseline_update BEFORE UPDATE ON snapshot_baseline
WHEN NEW.singleton IS NOT OLD.singleton OR NEW.user_id IS NOT OLD.user_id
 OR NOT EXISTS(SELECT 1 FROM snapshot_downloads WHERE snapshot_token=NEW.snapshot_token AND user_id=NEW.user_id AND state='APPLIED')
BEGIN SELECT RAISE(ABORT,'Only an applied snapshot may become baseline'); END;

-- P10-07: retain the failed operation unchanged. A resolution is separate
-- immutable evidence, optionally linked to a NEW request with a fresh op_id.
CREATE TABLE mutation_conflict_resolutions (
  original_op_id TEXT NOT NULL PRIMARY KEY REFERENCES local_mutations(op_id),
  user_id TEXT NOT NULL REFERENCES local_account(user_id),
  replacement_op_id TEXT UNIQUE REFERENCES local_mutations(op_id),
  original_attempt_count INTEGER NOT NULL CHECK (original_attempt_count>0),
  resolved_revision INTEGER NOT NULL CHECK (resolved_revision>0),
  server_snapshot TEXT NOT NULL CHECK (json_valid(server_snapshot) AND json_type(server_snapshot)='object'),
  choices TEXT NOT NULL CHECK (json_valid(choices) AND json_type(choices)='object'),
  order_root_op_id TEXT NOT NULL REFERENCES local_mutations(op_id),
  logical_order INTEGER NOT NULL CHECK (logical_order>0),
  created_at INTEGER NOT NULL,
  CHECK (replacement_op_id IS NULL OR replacement_op_id<>original_op_id),
  CHECK (json_type(server_snapshot,'$.revision') IS 'integer'
    AND json_extract(server_snapshot,'$.revision')=resolved_revision)
) WITHOUT ROWID;

CREATE TRIGGER conflict_resolution_valid_insert BEFORE INSERT ON mutation_conflict_resolutions BEGIN
  SELECT RAISE(ABORT,'Resolution requires the current revision conflict') WHERE NOT EXISTS (
    SELECT 1 FROM local_mutations m WHERE m.op_id=NEW.original_op_id
      AND m.user_id=NEW.user_id AND m.operation='PATCH'
      AND m.entity_type IN ('SONG','RECORDING','TAG') AND m.queue_state='CONFLICT'
      AND m.attempt_count=NEW.original_attempt_count
      AND json_extract(m.server_response,'$.status')=409
      AND json_extract(m.server_response,'$.code')='REVISION_CONFLICT'
      AND json_type(m.server_response,'$.current.revision')='integer'
      AND NEW.resolved_revision>=json_extract(m.server_response,'$.current.revision')
      AND NEW.resolved_revision>m.base_revision
      AND json_extract(NEW.server_snapshot,'$.id')=m.entity_id
      AND (json_type(NEW.server_snapshot,'$.user_id') IS NULL
        OR json_extract(NEW.server_snapshot,'$.user_id')=NEW.user_id)
  );
  SELECT RAISE(ABORT,'Resolution choice must be explicit') WHERE EXISTS (
    SELECT 1 FROM json_each(NEW.choices) AS choice WHERE choice.type<>'text' OR choice.value NOT IN ('LOCAL','SERVER')
  );
  SELECT RAISE(ABORT,'Mapping evidence must be resolved separately') WHERE EXISTS (
    SELECT 1 FROM mutation_mapping_holds WHERE op_id=NEW.original_op_id AND released_at IS NULL
  ) OR EXISTS (
    SELECT 1 FROM mutation_supersessions WHERE original_op_id=NEW.original_op_id OR replacement_op_id=NEW.original_op_id
  );
  SELECT RAISE(ABORT,'Invalid conflict replacement') WHERE NEW.replacement_op_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM local_mutations original JOIN local_mutations replacement ON replacement.op_id=NEW.replacement_op_id
    WHERE original.op_id=NEW.original_op_id AND replacement.user_id=NEW.user_id
      AND replacement.entity_type=original.entity_type AND replacement.entity_id=original.entity_id
      AND replacement.operation='PATCH' AND replacement.queue_state='PENDING' AND replacement.attempt_count=0
      AND replacement.rowid>original.rowid AND replacement.base_revision=NEW.resolved_revision
      AND replacement.base_payload=NEW.server_snapshot
      AND json_type(replacement.payload,'$.base_revision')='integer'
      AND json_extract(replacement.payload,'$.base_revision')=NEW.resolved_revision
      AND NOT EXISTS(SELECT 1 FROM mutation_wire_requests WHERE op_id=replacement.op_id)
  );
  SELECT RAISE(ABORT,'Conflict resolution order must be inherited') WHERE
    NEW.order_root_op_id IS NOT COALESCE((SELECT order_root_op_id FROM mutation_conflict_resolutions WHERE replacement_op_id=NEW.original_op_id),NEW.original_op_id)
    OR NEW.logical_order IS NOT COALESCE((SELECT logical_order FROM mutation_conflict_resolutions WHERE replacement_op_id=NEW.original_op_id),(SELECT logical_order FROM recording_followups WHERE replacement_op_id=NEW.original_op_id),(SELECT rowid FROM local_mutations WHERE op_id=NEW.original_op_id));
  SELECT RAISE(ABORT,'Cannot prepend a resolution chain') WHERE EXISTS (
    SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id=NEW.replacement_op_id
  );
END;

CREATE TRIGGER conflict_resolution_no_replace BEFORE INSERT ON mutation_conflict_resolutions
WHEN EXISTS(SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id=NEW.original_op_id
  OR (NEW.replacement_op_id IS NOT NULL AND replacement_op_id=NEW.replacement_op_id))
BEGIN SELECT RAISE(ABORT,'Conflict resolution evidence cannot be replaced'); END;

CREATE TRIGGER conflict_resolution_no_update BEFORE UPDATE ON mutation_conflict_resolutions
BEGIN SELECT RAISE(ABORT,'Conflict resolution evidence is immutable'); END;

CREATE TRIGGER conflict_resolution_no_delete BEFORE DELETE ON mutation_conflict_resolutions
BEGIN SELECT RAISE(ABORT,'Conflict resolution evidence must be retained'); END;

CREATE TRIGGER resolved_mutation_no_claim BEFORE UPDATE OF attempt_count ON local_mutations
WHEN NEW.attempt_count>OLD.attempt_count
 AND EXISTS(SELECT 1 FROM mutation_conflict_resolutions WHERE original_op_id=OLD.op_id)
BEGIN SELECT RAISE(ABORT,'Resolved original operation cannot be retried'); END;
