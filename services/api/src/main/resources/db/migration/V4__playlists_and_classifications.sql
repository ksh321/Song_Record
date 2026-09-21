-- P04-04. D06 overrides the original customizable Condition design.
CREATE TABLE playlist (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    name VARCHAR(100) NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    deleted_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_playlist_owner_id (user_id, id),
    KEY ix_playlist_owner_deleted (user_id, deleted_at, id),
    CONSTRAINT fk_playlist_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_playlist_name CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 100),
    CONSTRAINT ck_playlist_revision CHECK (revision > 0)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE playlist_item (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    playlist_id BINARY(16) NOT NULL,
    song_id BINARY(16) NULL,
    candidate_brand VARCHAR(2) CHARACTER SET ascii COLLATE ascii_bin NULL,
    candidate_number VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
    candidate_snapshot JSON NULL,
    entry_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
    position BIGINT NOT NULL,
    hidden_by_batch_id BINARY(16) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_playlist_item_owner_id (user_id, id),
    UNIQUE KEY uq_playlist_item_entry (playlist_id, entry_key),
    UNIQUE KEY uq_playlist_item_song (playlist_id, song_id),
    KEY ix_playlist_item_order (user_id, playlist_id, position, id),
    CONSTRAINT fk_playlist_item_playlist FOREIGN KEY (user_id, playlist_id)
        REFERENCES playlist (user_id, id),
    CONSTRAINT fk_playlist_item_song FOREIGN KEY (user_id, song_id)
        REFERENCES song (user_id, id),
    CONSTRAINT ck_playlist_item_position CHECK (position >= 0),
    CONSTRAINT ck_playlist_item_candidate CHECK (
        (candidate_brand IS NULL AND candidate_number IS NULL AND candidate_snapshot IS NULL)
        OR (candidate_brand IS NOT NULL AND candidate_brand = 'TJ'
            AND candidate_number IS NOT NULL AND candidate_number REGEXP '^[0-9]{1,20}$'
            AND candidate_snapshot IS NOT NULL AND JSON_TYPE(candidate_snapshot) = 'OBJECT')
    ),
    CONSTRAINT ck_playlist_item_target CHECK (song_id IS NOT NULL OR candidate_brand IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE tag (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    name VARCHAR(50) NOT NULL,
    -- D06: server supplies UTF-8(NFC(contract-trim(name)), ASCII A-Z -> a-z).
    -- Never use the display collation as the normalization algorithm.
    normalized_name_key VARBINARY(800) NOT NULL,
    active_name_key VARBINARY(800) GENERATED ALWAYS AS (
        CASE WHEN archived_at IS NULL THEN normalized_name_key ELSE NULL END
    ) STORED,
    archived_at DATETIME(3) NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_tag_owner_id (user_id, id),
    UNIQUE KEY uq_tag_owner_active_name (user_id, active_name_key),
    CONSTRAINT fk_tag_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_tag_name CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 50),
    CONSTRAINT ck_tag_key CHECK (OCTET_LENGTH(normalized_name_key) BETWEEN 1 AND 800),
    CONSTRAINT ck_tag_revision CHECK (revision > 0)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE recording_tag (
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    tag_id BINARY(16) NOT NULL,
    name_snapshot VARCHAR(50) NOT NULL DEFAULT '',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (recording_id, tag_id),
    KEY ix_recording_tag_owner_tag (user_id, tag_id, recording_id),
    CONSTRAINT fk_recording_tag_recording FOREIGN KEY (user_id, recording_id)
        REFERENCES recording (user_id, id),
    CONSTRAINT fk_recording_tag_tag FOREIGN KEY (user_id, tag_id)
        REFERENCES tag (user_id, id),
    CONSTRAINT ck_recording_tag_snapshot CHECK (CHAR_LENGTH(name_snapshot) BETWEEN 1 AND 50)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE condition_catalog (
    code VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    name VARCHAR(50) NOT NULL,
    display_order SMALLINT NOT NULL,
    catalog_version INT NOT NULL,
    PRIMARY KEY (code),
    UNIQUE KEY uq_condition_order (display_order),
    CONSTRAINT ck_condition_code CHECK (code IN ('VERY_GOOD', 'GOOD', 'NORMAL', 'BAD')),
    CONSTRAINT ck_condition_version CHECK (catalog_version > 0)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
INSERT INTO condition_catalog (code, name, display_order, catalog_version) VALUES
    ('VERY_GOOD', '매우 좋음', 1, 1), ('GOOD', '좋음', 2, 1),
    ('NORMAL', '보통', 3, 1), ('BAD', '안 좋음', 4, 1);
ALTER TABLE recording
    ADD COLUMN condition_code VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN condition_name_snapshot VARCHAR(50) NULL,
    ADD CONSTRAINT fk_recording_condition FOREIGN KEY (condition_code) REFERENCES condition_catalog (code),
    ADD CONSTRAINT ck_recording_condition_pair CHECK (
        (condition_code IS NULL AND condition_name_snapshot IS NULL)
        OR (condition_code IS NOT NULL AND condition_name_snapshot IS NOT NULL
            AND CHAR_LENGTH(condition_name_snapshot) BETWEEN 1 AND 50)
    );

DELIMITER $$
-- Centralized validation used on INSERT and UPDATE, including server-derived keys.
CREATE PROCEDURE p04_playlist_item_identity(
    IN owner_id BINARY(16), IN target_playlist BINARY(16), IN target_song BINARY(16),
    IN brand VARCHAR(2), IN candidate VARCHAR(20), IN snapshot JSON,
    IN check_active_song BOOLEAN, OUT computed_key VARCHAR(64)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE song_source_type VARCHAR(16) DEFAULT NULL;
    DECLARE song_number VARCHAR(20);
    DECLARE song_state VARCHAR(16);
    DECLARE playlist_deleted DATETIME(3);
    DECLARE found_playlist BINARY(16) DEFAULT NULL;
    SELECT id, deleted_at INTO found_playlist, playlist_deleted
      FROM playlist WHERE user_id = owner_id AND id = target_playlist FOR SHARE;
    IF found_playlist IS NULL OR playlist_deleted IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'An active owned playlist is required';
    END IF;
    IF target_song IS NOT NULL THEN
        SELECT source_type, tj_number, lifecycle_state INTO song_source_type, song_number, song_state
          FROM song WHERE user_id = owner_id AND id = target_song FOR SHARE;
        IF song_source_type IS NULL OR (check_active_song AND song_state <> 'ACTIVE') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'An active owned song is required for a new link';
        END IF;
        IF song_source_type = 'TJ' THEN
            IF brand IS NOT NULL AND (brand <> 'TJ' OR candidate IS NULL OR BINARY candidate <> BINARY song_number) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Candidate and linked TJ number must match';
            END IF;
            SET computed_key = CONCAT('tj:', song_number);
        ELSE
            IF brand IS NOT NULL OR candidate IS NOT NULL OR snapshot IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manual songs cannot carry external candidates';
            END IF;
            SET computed_key = CONCAT('manual:', LOWER(BIN_TO_UUID(target_song)));
        END IF;
    ELSE
        IF brand IS NULL OR brand <> 'TJ' OR candidate IS NULL OR snapshot IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'An unlinked item requires a TJ candidate';
        END IF;
        SET computed_key = CONCAT('tj:', candidate);
    END IF;
END$$
CREATE TRIGGER trg_playlist_item_before_insert
BEFORE INSERT ON playlist_item FOR EACH ROW
BEGIN
    DECLARE computed_key VARCHAR(64);
    CALL p04_playlist_item_identity(NEW.user_id, NEW.playlist_id, NEW.song_id,
        NEW.candidate_brand, NEW.candidate_number, NEW.candidate_snapshot, TRUE, computed_key);
    SET NEW.entry_key = computed_key;
END$$
CREATE TRIGGER trg_playlist_item_before_update
BEFORE UPDATE ON playlist_item FOR EACH ROW
BEGIN
    DECLARE computed_key VARCHAR(64);
    IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id OR NEW.playlist_id <> OLD.playlist_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Playlist item identity is immutable';
    END IF;
    CALL p04_playlist_item_identity(NEW.user_id, NEW.playlist_id, NEW.song_id,
        NEW.candidate_brand, NEW.candidate_number, NEW.candidate_snapshot,
        NOT (NEW.song_id <=> OLD.song_id), computed_key);
    IF BINARY computed_key <> BINARY OLD.entry_key THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Candidate linking must preserve entry identity';
    END IF;
    SET NEW.entry_key = computed_key;
END$$
CREATE TRIGGER trg_song_identity_before_update
BEFORE UPDATE ON song FOR EACH ROW
BEGIN
    IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id OR NEW.source_type <> OLD.source_type
       OR NOT (NEW.tj_number <=> OLD.tj_number) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Song identity and source number are immutable';
    END IF;
END$$
CREATE TRIGGER trg_recording_tag_before_insert
BEFORE INSERT ON recording_tag FOR EACH ROW
BEGIN
    DECLARE tag_name VARCHAR(50) DEFAULT NULL;
    DECLARE tag_archived DATETIME(3);
    SELECT name, archived_at INTO tag_name, tag_archived
      FROM tag WHERE user_id = NEW.user_id AND id = NEW.tag_id FOR SHARE;
    IF tag_name IS NULL OR tag_archived IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A new tag link requires an active owned tag';
    END IF;
    SET NEW.name_snapshot = tag_name;
END$$
CREATE TRIGGER trg_recording_tag_before_update
BEFORE UPDATE ON recording_tag FOR EACH ROW
BEGIN
    IF NEW.user_id <> OLD.user_id OR NEW.recording_id <> OLD.recording_id OR NEW.tag_id <> OLD.tag_id
       OR BINARY NEW.name_snapshot <> BINARY OLD.name_snapshot THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tag relationship and historical name are immutable';
    END IF;
END$$
CREATE TRIGGER trg_recording_condition_before_insert
BEFORE INSERT ON recording FOR EACH ROW
BEGIN
    SET NEW.condition_name_snapshot = (
        SELECT name FROM condition_catalog WHERE code = NEW.condition_code
    );
END$$
CREATE TRIGGER trg_recording_condition_before_update
BEFORE UPDATE ON recording FOR EACH ROW
BEGIN
    IF NOT (NEW.condition_code <=> OLD.condition_code) THEN
        SET NEW.condition_name_snapshot = (SELECT name FROM condition_catalog WHERE code = NEW.condition_code);
    ELSE
        SET NEW.condition_name_snapshot = OLD.condition_name_snapshot;
    END IF;
END$$
CREATE TRIGGER trg_condition_catalog_before_insert
BEFORE INSERT ON condition_catalog FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition catalog is read only';
END$$
CREATE TRIGGER trg_condition_catalog_before_update
BEFORE UPDATE ON condition_catalog FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition catalog is read only';
END$$
CREATE TRIGGER trg_condition_catalog_before_delete
BEFORE DELETE ON condition_catalog FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition catalog is read only';
END$$
DELIMITER ;

UPDATE app_schema_metadata SET schema_value = '4' WHERE schema_key = 'schema_contract';
