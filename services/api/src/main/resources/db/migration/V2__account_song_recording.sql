-- P04-01~03: account ownership, songs, recordings, and server-side file metadata.
-- UUIDs use BINARY(16), instants use UTC DATETIME(3), and user text uses utf8mb4.

CREATE TABLE app_user (
    id BINARY(16) NOT NULL,
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    CONSTRAINT ck_app_user_status CHECK (status IN ('ACTIVE', 'DELETING'))
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE device (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    display_name VARCHAR(200) NOT NULL,
    last_seen_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_device_owner_id (user_id, id),
    KEY ix_device_owner_seen (user_id, last_seen_at, id),
    CONSTRAINT fk_device_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_device_name_length CHECK (CHAR_LENGTH(display_name) BETWEEN 1 AND 200)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE auth_identity (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    provider VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider_user_id VARCHAR(255) COLLATE utf8mb4_bin NOT NULL,
    email VARCHAR(320) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_auth_identity_provider_user (provider, provider_user_id),
    UNIQUE KEY uq_auth_identity_owner_id (user_id, id),
    KEY ix_auth_identity_owner (user_id, id),
    CONSTRAINT fk_auth_identity_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_auth_identity_provider CHECK (provider IN ('GOOGLE', 'KAKAO')),
    CONSTRAINT ck_auth_identity_provider_user CHECK (CHAR_LENGTH(provider_user_id) BETWEEN 1 AND 255)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE auth_session (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    device_id BINARY(16) NOT NULL,
    refresh_hash BINARY(32) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_auth_session_refresh_hash (refresh_hash),
    UNIQUE KEY uq_auth_session_owner_id (user_id, id),
    KEY ix_auth_session_owner_device (user_id, device_id, expires_at),
    CONSTRAINT fk_auth_session_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT fk_auth_session_device FOREIGN KEY (user_id, device_id)
        REFERENCES device (user_id, id),
    CONSTRAINT ck_auth_session_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_auth_session_revoked CHECK (revoked_at IS NULL OR revoked_at >= created_at)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE user_entitlement (
    user_id BINARY(16) NOT NULL,
    plan_code VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'FREE',
    pinned_limit INT NOT NULL DEFAULT 10,
    quota_bytes BIGINT NOT NULL DEFAULT 1000000000,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_entitlement_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_user_entitlement_plan CHECK (plan_code = 'FREE'),
    CONSTRAINT ck_user_entitlement_limits CHECK (
        pinned_limit >= 0 AND quota_bytes >= 0 AND revision > 0
    )
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE song (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    source_type VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    tj_number VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
    reserved_tj_number VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin
        GENERATED ALWAYS AS (
            CASE
                WHEN source_type = 'TJ'
                 AND lifecycle_state IN ('ACTIVE', 'TRASHED', 'PURGE_PENDING')
                THEN tj_number
                ELSE NULL
            END
        ) STORED,
    title VARCHAR(200) NOT NULL,
    artist VARCHAR(200) NOT NULL,
    version_code VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'NORMAL',
    note TEXT NOT NULL,
    representative_key_mode VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL,
    representative_key_shift SMALLINT NULL,
    song_tier CHAR(1) CHARACTER SET ascii COLLATE ascii_bin NULL,
    representative_recording_id BINARY(16) NULL,
    lifecycle_state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE',
    deleted_at DATETIME(3) NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_song_owner_id (user_id, id),
    UNIQUE KEY uq_song_owner_reserved_tj (user_id, reserved_tj_number),
    KEY ix_song_owner_lifecycle_title (user_id, lifecycle_state, title, id),
    KEY ix_song_owner_lifecycle_updated (user_id, lifecycle_state, updated_at, id),
    CONSTRAINT fk_song_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_song_source_number CHECK (
        (source_type = 'TJ'
            AND tj_number IS NOT NULL
            AND CHAR_LENGTH(tj_number) BETWEEN 1 AND 20
            AND tj_number REGEXP '^[0-9]+$')
        OR (source_type = 'MANUAL' AND tj_number IS NULL)
    ),
    CONSTRAINT ck_song_title_length CHECK (CHAR_LENGTH(title) BETWEEN 1 AND 200),
    CONSTRAINT ck_song_artist_length CHECK (CHAR_LENGTH(artist) BETWEEN 1 AND 200),
    CONSTRAINT ck_song_note_length CHECK (CHAR_LENGTH(note) <= 2000),
    CONSTRAINT ck_song_version CHECK (version_code IN ('NORMAL', 'MR', 'LIVE')),
    CONSTRAINT ck_song_representative_key CHECK (
        (representative_key_mode IS NULL AND representative_key_shift IS NULL)
        OR (
            representative_key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND representative_key_shift BETWEEN -12 AND 12
            AND (representative_key_mode <> 'ORIGINAL' OR representative_key_shift = 0)
        )
    ),
    CONSTRAINT ck_song_tier CHECK (song_tier IS NULL OR song_tier IN ('S', 'A', 'B', 'C', 'D')),
    CONSTRAINT ck_song_lifecycle CHECK (
        lifecycle_state IN ('ACTIVE', 'TRASHED', 'PURGE_PENDING', 'PURGED')
    ),
    CONSTRAINT ck_song_deleted_at CHECK (
        (lifecycle_state = 'ACTIVE' AND deleted_at IS NULL)
        OR (lifecycle_state <> 'ACTIVE' AND deleted_at IS NOT NULL)
    ),
    CONSTRAINT ck_song_revision CHECK (revision > 0)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE song_source (
    song_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    provider VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_title VARCHAR(200) NOT NULL,
    source_artist VARCHAR(200) NOT NULL,
    source_ref VARCHAR(255) NOT NULL,
    verified_at DATETIME(3) NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (song_id),
    UNIQUE KEY uq_song_source_owner_song (user_id, song_id),
    CONSTRAINT fk_song_source_song FOREIGN KEY (user_id, song_id)
        REFERENCES song (user_id, id),
    CONSTRAINT ck_song_source_provider CHECK (provider = 'TJ'),
    CONSTRAINT ck_song_source_lengths CHECK (
        CHAR_LENGTH(source_title) BETWEEN 1 AND 200
        AND CHAR_LENGTH(source_artist) BETWEEN 1 AND 200
        AND CHAR_LENGTH(source_ref) BETWEEN 1 AND 255
    )
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE recording (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    origin_device_id BINARY(16) NOT NULL,
    song_id BINARY(16) NULL,
    title_snapshot VARCHAR(200) NULL,
    artist_snapshot VARCHAR(200) NULL,
    version_code VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'NORMAL',
    key_mode VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL,
    key_shift SMALLINT NULL,
    tier CHAR(1) CHARACTER SET ascii COLLATE ascii_bin NULL,
    note TEXT NOT NULL,
    recorded_at DATETIME(3) NOT NULL,
    timezone_id VARCHAR(64) NOT NULL,
    timezone_offset_minutes SMALLINT NOT NULL,
    metadata_state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DRAFT',
    lifecycle_state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE',
    revision BIGINT NOT NULL DEFAULT 1,
    link_revision BIGINT NOT NULL DEFAULT 1,
    deleted_at DATETIME(3) NULL,
    delete_batch_id BINARY(16) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_recording_owner_id (user_id, id),
    UNIQUE KEY uq_recording_owner_song_id (user_id, song_id, id),
    KEY ix_recording_owner_lifecycle_time (user_id, lifecycle_state, recorded_at, id),
    KEY ix_recording_owner_song_state_tier_time (
        user_id, song_id, lifecycle_state, metadata_state, tier, recorded_at, id
    ),
    CONSTRAINT fk_recording_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT fk_recording_device FOREIGN KEY (user_id, origin_device_id)
        REFERENCES device (user_id, id),
    CONSTRAINT fk_recording_song FOREIGN KEY (user_id, song_id)
        REFERENCES song (user_id, id),
    CONSTRAINT ck_recording_title_length CHECK (
        title_snapshot IS NULL OR CHAR_LENGTH(title_snapshot) BETWEEN 1 AND 200
    ),
    CONSTRAINT ck_recording_artist_length CHECK (
        artist_snapshot IS NULL OR CHAR_LENGTH(artist_snapshot) BETWEEN 1 AND 200
    ),
    CONSTRAINT ck_recording_note_length CHECK (CHAR_LENGTH(note) <= 2000),
    CONSTRAINT ck_recording_version CHECK (version_code IN ('NORMAL', 'MR', 'LIVE')),
    CONSTRAINT ck_recording_key CHECK (
        (key_mode IS NULL AND key_shift IS NULL)
        OR (
            key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND key_shift BETWEEN -12 AND 12
            AND (key_mode <> 'ORIGINAL' OR key_shift = 0)
        )
    ),
    CONSTRAINT ck_recording_tier CHECK (tier IS NULL OR tier IN ('S', 'A', 'B', 'C', 'D')),
    CONSTRAINT ck_recording_metadata CHECK (metadata_state IN ('DRAFT', 'SAVED')),
    CONSTRAINT ck_recording_saved_fields CHECK (
        metadata_state = 'DRAFT'
        OR (
            title_snapshot IS NOT NULL
            AND artist_snapshot IS NOT NULL
            AND key_mode IS NOT NULL
            AND key_shift IS NOT NULL
        )
    ),
    CONSTRAINT ck_recording_lifecycle CHECK (
        lifecycle_state IN ('ACTIVE', 'TRASHED', 'PURGE_PENDING', 'PURGED')
    ),
    CONSTRAINT ck_recording_deleted_at CHECK (
        (lifecycle_state = 'ACTIVE' AND deleted_at IS NULL)
        OR (lifecycle_state <> 'ACTIVE' AND deleted_at IS NOT NULL)
    ),
    CONSTRAINT ck_recording_timezone CHECK (
        CHAR_LENGTH(timezone_id) BETWEEN 1 AND 64
        AND timezone_offset_minutes BETWEEN -1080 AND 1080
    ),
    CONSTRAINT ck_recording_revisions CHECK (revision > 0 AND link_revision > 0)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE song
    ADD CONSTRAINT fk_song_representative_recording
    FOREIGN KEY (user_id, id, representative_recording_id)
    REFERENCES recording (user_id, song_id, id);

CREATE TABLE recording_file_spec (
    recording_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    size_bytes BIGINT NOT NULL,
    duration_ms INT NOT NULL,
    codec VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sample_rate INT NOT NULL,
    channels SMALLINT NOT NULL,
    capture_integrity VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (recording_id),
    UNIQUE KEY uq_recording_file_spec_owner (user_id, recording_id),
    CONSTRAINT fk_recording_file_spec_recording FOREIGN KEY (user_id, recording_id)
        REFERENCES recording (user_id, id),
    CONSTRAINT ck_recording_file_spec_sha CHECK (sha256 REGEXP '^[0-9a-f]{64}$'),
    CONSTRAINT ck_recording_file_spec_size CHECK (size_bytes BETWEEN 1 AND 6291456),
    CONSTRAINT ck_recording_file_spec_duration CHECK (duration_ms BETWEEN 1 AND 361000),
    CONSTRAINT ck_recording_file_spec_audio CHECK (
        codec = 'AAC_LC' AND sample_rate = 48000 AND channels = 1
    ),
    CONSTRAINT ck_recording_file_spec_integrity CHECK (
        capture_integrity IN ('VALIDATED', 'RECOVERED')
    )
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE recording_asset (
    recording_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    cloud_state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'NONE',
    blocked_reason VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    object_key VARCHAR(512) CHARACTER SET ascii COLLATE ascii_bin NULL,
    generation BIGINT NULL,
    verified_size BIGINT NULL,
    sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    stored_at DATETIME(3) NULL,
    cloud_revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (recording_id),
    UNIQUE KEY uq_recording_asset_owner (user_id, recording_id),
    UNIQUE KEY uq_recording_asset_object_key (object_key),
    KEY ix_recording_asset_owner_state (user_id, cloud_state, recording_id),
    CONSTRAINT fk_recording_asset_recording FOREIGN KEY (user_id, recording_id)
        REFERENCES recording (user_id, id),
    CONSTRAINT ck_recording_asset_state CHECK (
        cloud_state IN ('NONE', 'QUEUED', 'UPLOADING', 'VERIFYING', 'STORED', 'DELETING')
    ),
    CONSTRAINT ck_recording_asset_blocked CHECK (
        blocked_reason IS NULL
        OR blocked_reason IN (
            'FILE_MISSING', 'QUOTA', 'PIN_LIMIT', 'BUDGET',
            'AUTH', 'NETWORK', 'FILE_INVALID'
        )
    ),
    CONSTRAINT ck_recording_asset_sha CHECK (
        sha256 IS NULL OR sha256 REGEXP '^[0-9a-f]{64}$'
    ),
    CONSTRAINT ck_recording_asset_numbers CHECK (
        (generation IS NULL OR generation > 0)
        AND (verified_size IS NULL OR verified_size BETWEEN 1 AND 6291456)
        AND cloud_revision > 0
    ),
    CONSTRAINT ck_recording_asset_stored_fields CHECK (
        cloud_state NOT IN ('STORED', 'DELETING')
        OR (
            object_key IS NOT NULL
            AND generation IS NOT NULL
            AND verified_size IS NOT NULL
            AND sha256 IS NOT NULL
            AND stored_at IS NOT NULL
        )
    )
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE recording_upload (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    active_slot TINYINT NULL,
    active_recording_id BINARY(16)
        GENERATED ALWAYS AS (
            CASE
                WHEN state IN ('RESERVED', 'UPLOADING', 'VERIFYING') THEN recording_id
                ELSE NULL
            END
        ) STORED,
    expected_size BIGINT NOT NULL,
    expected_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    temp_key VARCHAR(512) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    final_key VARCHAR(512) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    policy_revision BIGINT NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    reservation_released_at DATETIME(3) NULL,
    error_code VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    lease_until DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_recording_upload_owner_id (user_id, id),
    UNIQUE KEY uq_recording_upload_temp_key (temp_key),
    UNIQUE KEY uq_recording_upload_final_key (final_key),
    UNIQUE KEY uq_recording_upload_owner_slot (user_id, active_slot),
    UNIQUE KEY uq_recording_upload_owner_active_recording (user_id, active_recording_id),
    KEY ix_recording_upload_expiry (state, expires_at, id),
    CONSTRAINT fk_recording_upload_recording FOREIGN KEY (user_id, recording_id)
        REFERENCES recording (user_id, id),
    CONSTRAINT ck_recording_upload_state CHECK (
        state IN (
            'RESERVED', 'UPLOADING', 'VERIFYING', 'COMMITTED',
            'FAILED', 'EXPIRED', 'CANCELLED'
        )
    ),
    CONSTRAINT ck_recording_upload_active_slot CHECK (
        (state IN ('RESERVED', 'UPLOADING', 'VERIFYING') AND active_slot IN (0, 1))
        OR (state IN ('COMMITTED', 'FAILED', 'EXPIRED', 'CANCELLED') AND active_slot IS NULL)
    ),
    CONSTRAINT ck_recording_upload_size CHECK (expected_size BETWEEN 1 AND 6291456),
    CONSTRAINT ck_recording_upload_sha CHECK (expected_sha256 REGEXP '^[0-9a-f]{64}$'),
    CONSTRAINT ck_recording_upload_policy CHECK (policy_revision > 0),
    CONSTRAINT ck_recording_upload_expiry CHECK (expires_at > created_at)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

DELIMITER $$

CREATE TRIGGER trg_song_source_before_insert
BEFORE INSERT ON song_source
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM song
        WHERE user_id = NEW.user_id
          AND id = NEW.song_id
          AND source_type = 'TJ'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SongSource requires an owned TJ song';
    END IF;
END$$

CREATE TRIGGER trg_song_source_before_update
BEFORE UPDATE ON song_source
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM song
        WHERE user_id = NEW.user_id
          AND id = NEW.song_id
          AND source_type = 'TJ'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SongSource requires an owned TJ song';
    END IF;
END$$

CREATE TRIGGER trg_recording_before_insert
BEFORE INSERT ON recording
FOR EACH ROW
BEGIN
    IF NEW.metadata_state <> 'DRAFT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A recording must be created as DRAFT';
    END IF;
END$$

CREATE TRIGGER trg_recording_before_update
BEFORE UPDATE ON recording
FOR EACH ROW
BEGIN
    IF OLD.metadata_state = 'SAVED' AND NEW.metadata_state <> 'SAVED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A SAVED recording cannot return to DRAFT';
    END IF;

    IF OLD.metadata_state = 'DRAFT' AND NEW.metadata_state = 'SAVED'
       AND NOT EXISTS (
           SELECT 1
           FROM recording_file_spec
           WHERE user_id = NEW.user_id
             AND recording_id = NEW.id
       ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A file specification is required before SAVED';
    END IF;
END$$

CREATE TRIGGER trg_recording_file_spec_before_update
BEFORE UPDATE ON recording_file_spec
FOR EACH ROW
BEGIN
    DECLARE parent_metadata_state VARCHAR(16);
    DECLARE parent_lifecycle_state VARCHAR(16);

    SELECT metadata_state, lifecycle_state
      INTO parent_metadata_state, parent_lifecycle_state
      FROM recording
     WHERE user_id = OLD.user_id
       AND id = OLD.recording_id;

    IF parent_metadata_state = 'SAVED' AND parent_lifecycle_state <> 'PURGED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A SAVED recording file specification is immutable';
    END IF;
END$$

CREATE TRIGGER trg_recording_file_spec_before_delete
BEFORE DELETE ON recording_file_spec
FOR EACH ROW
BEGIN
    DECLARE parent_metadata_state VARCHAR(16);
    DECLARE parent_lifecycle_state VARCHAR(16);

    SELECT metadata_state, lifecycle_state
      INTO parent_metadata_state, parent_lifecycle_state
      FROM recording
     WHERE user_id = OLD.user_id
       AND id = OLD.recording_id;

    IF parent_metadata_state = 'SAVED' AND parent_lifecycle_state <> 'PURGED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A SAVED recording file specification cannot be deleted';
    END IF;
END$$

DELIMITER ;

UPDATE app_schema_metadata
SET schema_value = '2'
WHERE schema_key = 'schema_contract';
