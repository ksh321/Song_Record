-- P04-06 / design 11.6. Storage structures only; no user/object deletion here.
-- All timestamps are UTC. P07 assigns sequences under the user_sync_state lock
-- and commits domain writes, receipts, change rows and jobs in ONE transaction.
CREATE TABLE user_sync_state (
    user_id BINARY(16) NOT NULL,
    last_change_seq BIGINT NOT NULL DEFAULT 0,
    retained_from_seq BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_sync_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_sync_sequences CHECK (last_change_seq >= 0 AND retained_from_seq > 0
        AND retained_from_seq - 1 <= last_change_seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
INSERT INTO user_sync_state (user_id) SELECT id FROM app_user;

CREATE TABLE change_log (
    user_id BINARY(16) NOT NULL,
    change_seq BIGINT NOT NULL,
    entity_type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    entity_id BINARY(16) NOT NULL,
    revision BIGINT NOT NULL,
    operation VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    payload JSON NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    expires_at DATETIME(3) NOT NULL DEFAULT (CURRENT_TIMESTAMP(3) + INTERVAL 90 DAY),
    PRIMARY KEY (user_id, change_seq),
    KEY ix_change_expiry (expires_at, user_id, change_seq),
    KEY ix_change_entity (user_id, entity_type, entity_id, change_seq),
    CONSTRAINT fk_change_sync FOREIGN KEY (user_id) REFERENCES user_sync_state (user_id),
    CONSTRAINT ck_change_numbers CHECK (change_seq > 0 AND revision > 0),
    CONSTRAINT ck_change_type CHECK (entity_type REGEXP '^[A-Z][A-Z0-9_]{0,63}$'),
    CONSTRAINT ck_change_operation CHECK (operation IN ('UPSERT', 'DELETE')),
    CONSTRAINT ck_change_payload CHECK (JSON_TYPE(payload) = 'OBJECT'),
    CONSTRAINT ck_change_expiry CHECK (expires_at = created_at + INTERVAL 90 DAY)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE mutation_receipt (
    user_id BINARY(16) NOT NULL,
    op_id BINARY(16) NOT NULL,
    request_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    response_status SMALLINT NOT NULL,
    response_body JSON NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    expires_at DATETIME(3) NOT NULL DEFAULT (CURRENT_TIMESTAMP(3) + INTERVAL 90 DAY),
    PRIMARY KEY (user_id, op_id),
    KEY ix_receipt_expiry (expires_at, user_id, op_id),
    CONSTRAINT fk_receipt_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_receipt_hash CHECK (request_hash REGEXP '^[0-9a-f]{64}$'),
    CONSTRAINT ck_receipt_status CHECK (response_status BETWEEN 200 AND 599),
    CONSTRAINT ck_receipt_no_content CHECK (response_status <> 204 OR response_body IS NULL),
    CONSTRAINT ck_receipt_expiry CHECK (expires_at = created_at + INTERVAL 90 DAY)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE deletion_batch (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    op_id BINARY(16) NOT NULL,
    mode VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    deleted_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    purge_after DATETIME(3) NOT NULL DEFAULT (CURRENT_TIMESTAMP(3) + INTERVAL 7 DAY),
    -- Opaque preview token: P20 defines its derivation, not a client timestamp.
    preview_version VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_batch_owner_id (user_id, id),
    UNIQUE KEY uq_batch_owner_op (user_id, op_id),
    KEY ix_batch_purge (purge_after, id),
    CONSTRAINT fk_batch_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_batch_mode CHECK (mode IN ('SONG_ONLY', 'SONG_AND_RECORDINGS', 'RECORDING')),
    CONSTRAINT ck_batch_expiry CHECK (purge_after = deleted_at + INTERVAL 7 DAY),
    CONSTRAINT ck_batch_preview CHECK (CHAR_LENGTH(preview_version) BETWEEN 1 AND 128)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE deletion_item (
    batch_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    entity_type VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    entity_id BINARY(16) NOT NULL,
    previous_song_id BINARY(16) NULL,
    previous_list_id BINARY(16) NULL,
    detached_link_revision BIGINT NULL,
    original_deleted_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (batch_id, entity_type, entity_id),
    KEY ix_deletion_item_owner_entity (user_id, entity_type, entity_id, batch_id),
    CONSTRAINT fk_deletion_item_batch FOREIGN KEY (user_id, batch_id)
        REFERENCES deletion_batch (user_id, id),
    CONSTRAINT ck_deletion_item_type CHECK (entity_type IN ('SONG', 'RECORDING', 'PLAYLIST_ITEM')),
    CONSTRAINT ck_deletion_item_link CHECK (
        (entity_type = 'SONG' AND previous_song_id IS NULL AND previous_list_id IS NULL AND detached_link_revision IS NULL)
        OR (entity_type = 'RECORDING' AND previous_list_id IS NULL
            AND (detached_link_revision IS NULL OR (previous_song_id IS NOT NULL AND detached_link_revision > 0)))
        OR (entity_type = 'PLAYLIST_ITEM' AND previous_list_id IS NOT NULL AND detached_link_revision IS NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Historical snapshots intentionally do not FK back to the mutable/live target.
-- Their ownership is checked at INSERT below; subsequent updates are forbidden.
-- Existing invalid batch references stop the migration instead of being erased.
ALTER TABLE recording ADD CONSTRAINT fk_recording_deletion_batch
    FOREIGN KEY (user_id, delete_batch_id) REFERENCES deletion_batch (user_id, id);
ALTER TABLE playlist_item ADD CONSTRAINT fk_playlist_item_hidden_batch
    FOREIGN KEY (user_id, hidden_by_batch_id) REFERENCES deletion_batch (user_id, id);

CREATE TABLE deletion_ledger (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    entity_type VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    entity_id BINARY(16) NOT NULL,
    object_generation BINARY(16) NULL,
    generation_key BINARY(16) GENERATED ALWAYS AS
        (COALESCE(object_generation, UNHEX('00000000000000000000000000000000'))) STORED,
    revision BIGINT NOT NULL,
    purged_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_ledger_subject (user_id, entity_type, entity_id, generation_key),
    KEY ix_ledger_purged (purged_at, user_id),
    -- No live-user/target FK: the ledger must survive physical account deletion.
    -- No 90-day expires_at: active-account tombstones outlive change_log/receipts.
    CONSTRAINT ck_ledger_type CHECK (entity_type IN ('USER', 'SONG', 'RECORDING', 'PLAYLIST', 'PLAYLIST_ITEM', 'TAG', 'RECORDING_ASSET')),
    CONSTRAINT ck_ledger_generation CHECK (
        (entity_type = 'RECORDING_ASSET' AND object_generation IS NOT NULL
            AND object_generation <> UNHEX('00000000000000000000000000000000'))
        OR (entity_type <> 'RECORDING_ASSET' AND object_generation IS NULL)
    ),
    CONSTRAINT ck_ledger_user_target CHECK (entity_type <> 'USER' OR entity_id = user_id),
    CONSTRAINT ck_ledger_revision CHECK (revision > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE job (
    id BINARY(16) NOT NULL,
    -- NULL is reserved for global maintenance jobs. No live-user FK: account
    -- deletion/backup cleanup must continue after the account row is gone.
    user_id BINARY(16) NULL,
    type VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    aggregate_id BINARY(16) NOT NULL,
    dedupe_key VARBINARY(255) NOT NULL,
    payload JSON NOT NULL,
    state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'QUEUED',
    attempt_count INT NOT NULL DEFAULT 0,
    run_after DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    lease_token BINARY(16) NULL,
    claimed_at DATETIME(3) NULL,
    lease_until DATETIME(3) NULL,
    last_error VARCHAR(512) NULL,
    finished_at DATETIME(3) NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_job_dedupe (dedupe_key),
    KEY ix_job_ready (state, run_after, id),
    KEY ix_job_lease (state, lease_until, id),
    KEY ix_job_owner_aggregate (user_id, type, aggregate_id, id),
    CONSTRAINT ck_job_type CHECK (type REGEXP '^[A-Z][A-Z0-9_]{0,63}$'),
    CONSTRAINT ck_job_dedupe CHECK (OCTET_LENGTH(dedupe_key) BETWEEN 1 AND 255),
    CONSTRAINT ck_job_payload CHECK (JSON_TYPE(payload) = 'OBJECT'),
    CONSTRAINT ck_job_state CHECK (state IN ('QUEUED', 'RUNNING', 'RETRY_WAIT', 'SUCCEEDED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_job_numbers CHECK (attempt_count >= 0 AND revision > 0),
    CONSTRAINT ck_job_lease CHECK (
        (state = 'RUNNING' AND lease_token IS NOT NULL AND claimed_at IS NOT NULL
            AND lease_until IS NOT NULL AND lease_until > claimed_at AND attempt_count > 0)
        OR (state <> 'RUNNING' AND lease_token IS NULL AND claimed_at IS NULL AND lease_until IS NULL)
    ),
    CONSTRAINT ck_job_completion CHECK (
        (state IN ('SUCCEEDED', 'FAILED', 'CANCELLED') AND finished_at IS NOT NULL AND finished_at >= created_at)
        OR (state NOT IN ('SUCCEEDED', 'FAILED', 'CANCELLED') AND finished_at IS NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DELIMITER $$
CREATE TRIGGER trg_sync_before_update BEFORE UPDATE ON user_sync_state FOR EACH ROW
BEGIN
    IF NEW.user_id <> OLD.user_id OR NEW.last_change_seq < OLD.last_change_seq
        OR NEW.retained_from_seq < OLD.retained_from_seq THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sync identity and cursors cannot move backwards';
    END IF;
END$$
CREATE TRIGGER trg_change_before_update BEFORE UPDATE ON change_log FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Change history is immutable';
END$$
CREATE TRIGGER trg_receipt_before_update BEFORE UPDATE ON mutation_receipt FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Mutation response and expiry are immutable';
END$$
CREATE TRIGGER trg_batch_before_update BEFORE UPDATE ON deletion_batch FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion batch snapshot and expiry are immutable';
END$$
CREATE TRIGGER trg_deletion_item_before_insert BEFORE INSERT ON deletion_item FOR EACH ROW
BEGIN
    DECLARE owned INT DEFAULT 0;
    DECLARE linked_song BINARY(16) DEFAULT NULL;
    DECLARE linked_list BINARY(16) DEFAULT NULL;
    DECLARE prior_deleted_at DATETIME(3) DEFAULT NULL;
    IF NEW.entity_type = 'SONG' THEN
        SELECT COUNT(*) INTO owned FROM song WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
        SELECT deleted_at INTO prior_deleted_at FROM song WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
    ELSEIF NEW.entity_type = 'RECORDING' THEN
        SELECT COUNT(*) INTO owned FROM recording WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
        SELECT song_id,deleted_at INTO linked_song,prior_deleted_at FROM recording
            WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
        IF NOT (NEW.previous_song_id <=> linked_song) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capture the recording link before detaching it';
        END IF;
    ELSEIF NEW.entity_type = 'PLAYLIST_ITEM' THEN
        SELECT COUNT(*) INTO owned FROM playlist_item WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
        SELECT song_id,playlist_id INTO linked_song,linked_list FROM playlist_item
            WHERE user_id=NEW.user_id AND id=NEW.entity_id FOR SHARE;
        IF NOT (NEW.previous_song_id <=> linked_song) OR NOT (NEW.previous_list_id <=> linked_list) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capture the actual playlist item links';
        END IF;
    END IF;
    IF owned <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion item must reference an existing owned entity';
    END IF;
    SET NEW.original_deleted_at = prior_deleted_at;
END$$
CREATE TRIGGER trg_deletion_item_before_update BEFORE UPDATE ON deletion_item FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion item history is immutable';
END$$
CREATE TRIGGER trg_ledger_before_update BEFORE UPDATE ON deletion_ledger FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deletion ledger identity and purge time are immutable';
END$$
CREATE TRIGGER trg_job_before_update BEFORE UPDATE ON job FOR EACH ROW
BEGIN
    IF NEW.id <> OLD.id OR NOT (NEW.user_id <=> OLD.user_id) OR NEW.type <> OLD.type
        OR NEW.aggregate_id <> OLD.aggregate_id OR NEW.dedupe_key <> OLD.dedupe_key
        OR NOT (NEW.payload <=> OLD.payload) OR NEW.created_at <> OLD.created_at
        OR NEW.attempt_count < OLD.attempt_count OR NEW.revision < OLD.revision THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Job identity is immutable and counters cannot decrease';
    END IF;
END$$
DELIMITER ;

-- P07/P20/P23/P24 own sequence allocation, polymorphic ownership/authorization,
-- TTL cleanup, legal state transitions, fencing checks and actual deletion I/O.
UPDATE app_schema_metadata SET schema_value = '6' WHERE schema_key = 'schema_contract';
