-- P04-01~03 audit. Never change the checksum of an applied V2.
-- CHECK accepts UNKNOWN in MySQL: optional pairs need explicit non-null guards.
-- Existing malformed rows deliberately stop migration; do not guess user values.
ALTER TABLE song DROP CHECK ck_song_representative_key,
    ADD CONSTRAINT ck_song_representative_key CHECK (
        (representative_key_mode IS NULL AND representative_key_shift IS NULL)
        OR (representative_key_mode IS NOT NULL AND representative_key_shift IS NOT NULL
            AND representative_key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND representative_key_shift BETWEEN -12 AND 12
            AND (representative_key_mode <> 'ORIGINAL' OR representative_key_shift = 0))
    );

ALTER TABLE recording DROP CHECK ck_recording_key,
    ADD CONSTRAINT ck_recording_key CHECK (
        (key_mode IS NULL AND key_shift IS NULL)
        OR (key_mode IS NOT NULL AND key_shift IS NOT NULL
            AND key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND key_shift BETWEEN -12 AND 12
            AND (key_mode <> 'ORIGINAL' OR key_shift = 0))
    );

ALTER TABLE recording_upload DROP CHECK ck_recording_upload_active_slot,
    ADD CONSTRAINT ck_recording_upload_active_slot CHECK (
        (state IN ('RESERVED', 'UPLOADING', 'VERIFYING')
            AND active_slot IS NOT NULL AND active_slot IN (0, 1))
        OR (state IN ('COMMITTED', 'FAILED', 'EXPIRED', 'CANCELLED') AND active_slot IS NULL)
    );

-- Spec 11.6 requires a fresh UUID for every object generation. Keep legacy
-- numbers for audit/migration mapping; object keys and file bytes are unchanged.
ALTER TABLE recording_asset
    DROP CHECK ck_recording_asset_numbers,
    DROP CHECK ck_recording_asset_stored_fields,
    CHANGE COLUMN generation legacy_generation BIGINT NULL,
    ADD COLUMN generation BINARY(16) NULL AFTER legacy_generation;
UPDATE recording_asset SET generation = UUID_TO_BIN(UUID()) WHERE legacy_generation IS NOT NULL;
ALTER TABLE recording_asset
    ADD UNIQUE KEY uq_recording_asset_generation (generation),
    ADD CONSTRAINT ck_recording_asset_numbers CHECK (
        (legacy_generation IS NULL OR legacy_generation > 0)
        AND (verified_size IS NULL OR verified_size BETWEEN 1 AND 6291456)
        AND cloud_revision > 0
    ),
    ADD CONSTRAINT ck_recording_asset_stored_fields CHECK (
        cloud_state NOT IN ('STORED', 'DELETING') OR (
            object_key IS NOT NULL AND CHAR_LENGTH(object_key) > 0
            AND generation IS NOT NULL AND verified_size IS NOT NULL
            AND sha256 IS NOT NULL AND stored_at IS NOT NULL
        )
    );

-- File-spec deletion/update and SAVED promotion must serialize on the parent.
-- Nonlocking SELECTs in V2 could observe DRAFT while another transaction saved it.
DROP TRIGGER trg_recording_file_spec_before_update;
DROP TRIGGER trg_recording_file_spec_before_delete;
DROP TRIGGER trg_recording_before_update;
DELIMITER $$
CREATE TRIGGER trg_recording_before_update
BEFORE UPDATE ON recording FOR EACH ROW
BEGIN
    DECLARE file_count INT DEFAULT 0;
    IF OLD.metadata_state = 'SAVED' AND NEW.metadata_state <> 'SAVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A SAVED recording cannot return to DRAFT';
    END IF;
    IF OLD.metadata_state = 'DRAFT' AND NEW.metadata_state = 'SAVED' THEN
        SELECT COUNT(*) INTO file_count FROM recording_file_spec
          WHERE user_id = NEW.user_id AND recording_id = NEW.id FOR SHARE;
        IF file_count = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A file specification is required before SAVED';
        END IF;
    END IF;
END$$
CREATE TRIGGER trg_recording_file_spec_before_update
BEFORE UPDATE ON recording_file_spec FOR EACH ROW
BEGIN
    DECLARE parent_metadata_state VARCHAR(16);
    DECLARE parent_lifecycle_state VARCHAR(16);
    SELECT metadata_state, lifecycle_state INTO parent_metadata_state, parent_lifecycle_state
      FROM recording WHERE user_id = OLD.user_id AND id = OLD.recording_id FOR UPDATE;
    IF parent_metadata_state = 'SAVED' AND parent_lifecycle_state <> 'PURGED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A SAVED recording file specification is immutable';
    END IF;
    IF NOT (NEW.recording_id <=> OLD.recording_id) OR NOT (NEW.user_id <=> OLD.user_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'File specification ownership is immutable';
    END IF;
END$$
CREATE TRIGGER trg_recording_file_spec_before_delete
BEFORE DELETE ON recording_file_spec FOR EACH ROW
BEGIN
    DECLARE parent_metadata_state VARCHAR(16);
    DECLARE parent_lifecycle_state VARCHAR(16);
    SELECT metadata_state, lifecycle_state INTO parent_metadata_state, parent_lifecycle_state
      FROM recording WHERE user_id = OLD.user_id AND id = OLD.recording_id FOR UPDATE;
    IF parent_metadata_state = 'SAVED' AND parent_lifecycle_state <> 'PURGED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A SAVED recording file specification cannot be deleted';
    END IF;
END$$
DELIMITER ;

UPDATE app_schema_metadata SET schema_value = '3' WHERE schema_key = 'schema_contract';
