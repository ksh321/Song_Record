-- P04-05 / design 11.5. Policy roles, pin slots, holds, cleanup attempts and
-- physical bytes are separate. No object I/O or automatic deletion in this migration.
CREATE TABLE song_cloud_selection (
    song_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    representative_id BINARY(16) NULL,
    latest_id BINARY(16) NULL,
    lowest_tier_id BINARY(16) NULL,
    selection_revision BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (song_id),
    UNIQUE KEY uq_selection_owner_song (user_id, song_id),
    CONSTRAINT fk_selection_song FOREIGN KEY (user_id, song_id) REFERENCES song (user_id, id),
    CONSTRAINT fk_selection_representative FOREIGN KEY (user_id, song_id, representative_id)
        REFERENCES recording (user_id, song_id, id),
    CONSTRAINT fk_selection_latest FOREIGN KEY (user_id, song_id, latest_id)
        REFERENCES recording (user_id, song_id, id),
    CONSTRAINT fk_selection_lowest FOREIGN KEY (user_id, song_id, lowest_tier_id)
        REFERENCES recording (user_id, song_id, id),
    CONSTRAINT ck_selection_revision CHECK (selection_revision > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Slots are one-based. Limits come from user_entitlement, not a hard-coded 10.
-- Lowering a limit must not erase current/pending protections.
CREATE TABLE pin_slot (
    user_id BINARY(16) NOT NULL,
    slot_no INT NOT NULL,
    current_recording_id BINARY(16) NULL,
    pending_recording_id BINARY(16) NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    operation_id BINARY(16) NULL,
    requested_at DATETIME(3) NULL,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id, slot_no),
    UNIQUE KEY uq_pin_current (user_id, current_recording_id),
    UNIQUE KEY uq_pin_pending (user_id, pending_recording_id),
    CONSTRAINT fk_pin_entitlement FOREIGN KEY (user_id) REFERENCES user_entitlement (user_id),
    CONSTRAINT fk_pin_current FOREIGN KEY (user_id, current_recording_id) REFERENCES recording (user_id, id),
    CONSTRAINT fk_pin_pending FOREIGN KEY (user_id, pending_recording_id) REFERENCES recording (user_id, id),
    CONSTRAINT ck_pin_numbers CHECK (slot_no > 0 AND revision > 0),
    CONSTRAINT ck_pin_distinct CHECK (
        current_recording_id IS NULL OR pending_recording_id IS NULL
        OR current_recording_id <> pending_recording_id
    ),
    CONSTRAINT ck_pin_request CHECK (
        ((operation_id IS NULL AND requested_at IS NULL)
            OR (operation_id IS NOT NULL AND requested_at IS NOT NULL))
        AND ((current_recording_id IS NULL AND pending_recording_id IS NULL)
            OR (operation_id IS NOT NULL AND requested_at IS NOT NULL))
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE cloud_hold (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    reason VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    related_operation_id BINARY(16) NULL,
    required_selection_revision BIGINT NULL,
    -- NULL means a single standing hold for this reason, not unlimited duplicates.
    operation_key BINARY(16) GENERATED ALWAYS AS
        (COALESCE(related_operation_id, UNHEX('00000000000000000000000000000000'))) STORED,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_hold_reason_operation (user_id, recording_id, reason, operation_key),
    KEY ix_hold_operation (user_id, related_operation_id),
    CONSTRAINT fk_hold_recording FOREIGN KEY (user_id, recording_id) REFERENCES recording (user_id, id),
    CONSTRAINT ck_hold_reason CHECK (reason IN ('PENDING_REPLACEMENT', 'WAITING_LOCAL_CONFIRM', 'ORPHAN_KEEP')),
    CONSTRAINT ck_hold_revision CHECK (required_selection_revision IS NULL OR required_selection_revision > 0),
    CONSTRAINT ck_hold_operation CHECK (related_operation_id IS NULL
        OR related_operation_id <> UNHEX('00000000000000000000000000000000')),
    CONSTRAINT ck_hold_replacement CHECK (reason <> 'PENDING_REPLACEMENT'
        OR (related_operation_id IS NOT NULL AND required_selection_revision IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE cloud_cleanup (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    generation BINARY(16) NOT NULL,
    expected_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    expected_cloud_revision BIGINT NOT NULL,
    confirmation_mode VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    confirmed_at DATETIME(3) NULL,
    confirmation_expires_at DATETIME(3) NULL,
    state VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'WAITING_CONFIRMATION',
    active_generation BINARY(16) GENERATED ALWAYS AS (
        CASE WHEN state IN ('WAITING_CONFIRMATION', 'CONFIRMED', 'DELETING', 'RETRY_WAIT')
            THEN generation ELSE NULL END
    ) STORED,
    lease_until DATETIME(3) NULL,
    error_code VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    completed_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_cleanup_active_generation (active_generation),
    KEY ix_cleanup_owner_recording (user_id, recording_id, created_at, id),
    KEY ix_cleanup_worker (state, lease_until, id),
    -- Keep attempt history when RecordingAsset moves on to a new generation.
    -- Deliberately no FK to the asset's mutable generation/revision.
    CONSTRAINT fk_cleanup_recording FOREIGN KEY (user_id, recording_id) REFERENCES recording (user_id, id),
    CONSTRAINT ck_cleanup_revision CHECK (expected_cloud_revision > 0),
    CONSTRAINT ck_cleanup_sha CHECK (expected_sha256 REGEXP '^[0-9a-f]{64}$'),
    CONSTRAINT ck_cleanup_state CHECK (state IN (
        'WAITING_CONFIRMATION', 'CONFIRMED', 'DELETING', 'RETRY_WAIT', 'SUCCEEDED', 'CANCELLED', 'EXPIRED'
    )),
    CONSTRAINT ck_cleanup_confirmation CHECK (
        (confirmation_mode IS NULL AND confirmed_at IS NULL AND confirmation_expires_at IS NULL)
        OR (confirmation_mode IS NOT NULL AND confirmed_at IS NOT NULL AND confirmation_expires_at IS NOT NULL
            AND confirmation_mode IN ('LOCAL_VERIFIED', 'USER_CONFIRMED_LOSS')
            AND confirmation_expires_at > confirmed_at
            AND TIMESTAMPDIFF(MICROSECOND, confirmed_at, confirmation_expires_at) <= 900000000)
    ),
    CONSTRAINT ck_cleanup_authorized CHECK (state NOT IN ('CONFIRMED', 'DELETING', 'RETRY_WAIT', 'SUCCEEDED')
        OR (confirmation_mode IS NOT NULL AND confirmed_at IS NOT NULL AND confirmation_expires_at IS NOT NULL)),
    CONSTRAINT ck_cleanup_completion CHECK (
        (state IN ('SUCCEEDED', 'CANCELLED', 'EXPIRED') AND completed_at IS NOT NULL AND completed_at >= created_at)
        OR (state NOT IN ('SUCCEEDED', 'CANCELLED', 'EXPIRED') AND completed_at IS NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE storage_usage (
    user_id BINARY(16) NOT NULL,
    used_bytes BIGINT NOT NULL DEFAULT 0,
    reserved_bytes BIGINT NOT NULL DEFAULT 0,
    revision BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_storage_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_storage_numbers CHECK (used_bytes >= 0 AND reserved_bytes >= 0 AND revision > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE global_storage_usage (
    id TINYINT NOT NULL,
    used_bytes BIGINT NOT NULL DEFAULT 0,
    reserved_bytes BIGINT NOT NULL DEFAULT 0,
    primary_quota_bytes BIGINT NOT NULL DEFAULT 20000000000,
    temp_observed_bytes BIGINT NOT NULL DEFAULT 0,
    upload_locked BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    CONSTRAINT ck_global_singleton CHECK (id = 1),
    CONSTRAINT ck_global_numbers CHECK (used_bytes >= 0 AND reserved_bytes >= 0
        AND primary_quota_bytes >= 0 AND temp_observed_bytes >= 0 AND revision > 0),
    CONSTRAINT ck_global_locked CHECK (upload_locked IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- One-time upgrade accounting: count physical assets, not policy references.
-- DELETING bytes remain used until object deletion is confirmed. No quota CHECK:
-- lowering entitlement must preserve over-quota existing data.
INSERT INTO storage_usage (user_id, used_bytes, reserved_bytes)
SELECT u.id, COALESCE(a.used_bytes, 0), COALESCE(r.reserved_bytes, 0)
FROM app_user u
LEFT JOIN (
    SELECT user_id, SUM(verified_size) used_bytes FROM recording_asset
    WHERE cloud_state IN ('STORED', 'DELETING') GROUP BY user_id
) a ON a.user_id = u.id
LEFT JOIN (
    SELECT user_id, SUM(expected_size) reserved_bytes FROM recording_upload
    WHERE state IN ('RESERVED', 'UPLOADING', 'VERIFYING') GROUP BY user_id
) r ON r.user_id = u.id;
INSERT INTO global_storage_usage (id, used_bytes, reserved_bytes)
SELECT 1, COALESCE(SUM(used_bytes), 0), COALESCE(SUM(reserved_bytes), 0) FROM storage_usage;

DELIMITER $$
-- Entitlement is the per-user serialization row. Locking reads see committed
-- slots even when the caller already established an older REPEATABLE READ snapshot.
CREATE PROCEDURE p04_validate_pin(
    IN owner_id BINARY(16), IN slot_number INT,
    IN current_id BINARY(16), IN pending_id BINARY(16),
    IN was_occupied BOOLEAN, IN old_current BINARY(16), IN old_pending BINARY(16)
)
BEGIN
    DECLARE pin_limit INT DEFAULT NULL;
    DECLARE occupied INT DEFAULT 0;
    DECLARE duplicates INT DEFAULT 0;
    DECLARE valid_recording INT DEFAULT 0;
    DECLARE asset_state VARCHAR(16) DEFAULT NULL;
    SELECT pinned_limit INTO pin_limit FROM user_entitlement WHERE user_id = owner_id FOR UPDATE;
    IF pin_limit IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A pin requires the owner entitlement';
    END IF;
    IF current_id IS NOT NULL OR pending_id IS NOT NULL THEN
        SELECT COUNT(*) INTO occupied FROM pin_slot
          WHERE user_id = owner_id AND slot_no <> slot_number
            AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL) FOR SHARE;
        IF NOT was_occupied AND (slot_number > pin_limit OR occupied >= pin_limit) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PIN_LIMIT';
        END IF;
        SELECT COUNT(*) INTO duplicates FROM pin_slot
          WHERE user_id = owner_id AND slot_no <> slot_number
            AND (current_recording_id IN (current_id, pending_id)
                OR pending_recording_id IN (current_id, pending_id)) FOR SHARE;
        IF duplicates > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Recording already occupies a pin slot';
        END IF;
    END IF;
    IF current_id IS NOT NULL AND NOT (current_id <=> old_current) THEN
        SELECT COUNT(*) INTO valid_recording FROM recording WHERE user_id = owner_id AND id = current_id
            AND lifecycle_state = 'ACTIVE' AND metadata_state = 'SAVED' FOR SHARE;
        SET asset_state = NULL;
        SELECT cloud_state INTO asset_state FROM recording_asset
            WHERE user_id = owner_id AND recording_id = current_id FOR SHARE;
        IF valid_recording <> 1 OR asset_state IS NULL OR asset_state <> 'STORED' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Current pin requires an ACTIVE SAVED STORED recording';
        END IF;
    END IF;
    IF pending_id IS NOT NULL AND NOT (pending_id <=> old_pending) THEN
        SELECT COUNT(*) INTO valid_recording FROM recording WHERE user_id = owner_id AND id = pending_id
            AND lifecycle_state = 'ACTIVE' AND metadata_state = 'SAVED' FOR SHARE;
        SET asset_state = NULL;
        SELECT cloud_state INTO asset_state FROM recording_asset
            WHERE user_id = owner_id AND recording_id = pending_id FOR SHARE;
        IF valid_recording <> 1 OR asset_state = 'DELETING' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pending pin requires an eligible recording outside cleanup';
        END IF;
    END IF;
END$$
CREATE TRIGGER trg_pin_before_insert BEFORE INSERT ON pin_slot FOR EACH ROW
BEGIN
    CALL p04_validate_pin(NEW.user_id, NEW.slot_no, NEW.current_recording_id, NEW.pending_recording_id,
        FALSE, NULL, NULL);
END$$
CREATE TRIGGER trg_pin_before_update BEFORE UPDATE ON pin_slot FOR EACH ROW
BEGIN
    IF NEW.user_id <> OLD.user_id OR NEW.slot_no <> OLD.slot_no THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pin slot identity is immutable';
    END IF;
    CALL p04_validate_pin(NEW.user_id, NEW.slot_no, NEW.current_recording_id, NEW.pending_recording_id,
        OLD.current_recording_id IS NOT NULL OR OLD.pending_recording_id IS NOT NULL,
        OLD.current_recording_id, OLD.pending_recording_id);
END$$
CREATE TRIGGER trg_cleanup_before_insert BEFORE INSERT ON cloud_cleanup FOR EACH ROW
BEGIN
    DECLARE matching_asset INT DEFAULT 0;
    SELECT COUNT(*) INTO matching_asset FROM recording_asset
        WHERE user_id = NEW.user_id AND recording_id = NEW.recording_id
          AND generation = NEW.generation AND sha256 = NEW.expected_sha256
          AND cloud_revision = NEW.expected_cloud_revision AND cloud_state = 'STORED' FOR SHARE;
    IF matching_asset <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cleanup must capture the current owned STORED object';
    END IF;
END$$
CREATE TRIGGER trg_cleanup_before_update BEFORE UPDATE ON cloud_cleanup FOR EACH ROW
BEGIN
    IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id OR NEW.recording_id <> OLD.recording_id
        OR NEW.generation <> OLD.generation OR NEW.expected_sha256 <> OLD.expected_sha256
        OR NEW.expected_cloud_revision <> OLD.expected_cloud_revision THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cleanup captured object identity is immutable';
    END IF;
END$$
DELIMITER ;

-- P11/P12/P13 must update policy + asset.cloud_revision and used/reserved in
-- their locked business transaction. These tables do not claim that I/O occurred.
UPDATE app_schema_metadata SET schema_value = '5' WHERE schema_key = 'schema_contract';
