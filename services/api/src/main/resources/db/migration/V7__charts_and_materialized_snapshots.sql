-- P04-07. D12 supersedes the historical ChartMonth model. D09 snapshots
-- contain personal metadata only, never audio bytes or authentication secrets.
CREATE TABLE chart_snapshot (
    id BINARY(16) NOT NULL,
    brand VARCHAR(2) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'MANANA',
    source_url VARCHAR(512) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    fetched_at DATETIME(3) NOT NULL,
    revision BIGINT NOT NULL,
    state VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'STAGING',
    item_count INT NOT NULL DEFAULT 0,
    published_at DATETIME(3) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_chart_scope_id (brand, period, id),
    UNIQUE KEY uq_chart_scope_revision (brand, period, revision),
    KEY ix_chart_cleanup (state, fetched_at, id),
    CONSTRAINT ck_chart_brand CHECK (brand IN ('TJ', 'KY')),
    CONSTRAINT ck_chart_period CHECK (period IN ('DAILY', 'WEEKLY', 'MONTHLY')),
    CONSTRAINT ck_chart_provider CHECK (provider = 'MANANA'),
    CONSTRAINT ck_chart_source CHECK (source_url = CONCAT('https://api.manana.kr/karaoke/popular/',
        IF(brand='TJ','tj','kumyoung'),'/',LOWER(period),'.json')),
    CONSTRAINT ck_chart_numbers CHECK (revision > 0 AND item_count >= 0),
    CONSTRAINT ck_chart_state CHECK (
        (state='STAGING' AND published_at IS NULL AND item_count=0)
        OR (state='PUBLISHED' AND published_at IS NOT NULL AND published_at>=fetched_at AND item_count>0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE chart_item (
    snapshot_id BINARY(16) NOT NULL,
    position INT NOT NULL,
    brand VARCHAR(2) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    number VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    title VARCHAR(200) NOT NULL,
    artist VARCHAR(200) NOT NULL,
    PRIMARY KEY (snapshot_id, position),
    UNIQUE KEY uq_chart_item_number (snapshot_id, number),
    CONSTRAINT fk_chart_item_scope FOREIGN KEY (brand, period, snapshot_id)
        REFERENCES chart_snapshot (brand, period, id) ON DELETE CASCADE,
    CONSTRAINT ck_chart_item_position CHECK (position>0),
    CONSTRAINT ck_chart_item_number CHECK (number REGEXP '^[0-9]{1,20}$'),
    CONSTRAINT ck_chart_item_text CHECK (CHAR_LENGTH(TRIM(title))>0 AND CHAR_LENGTH(TRIM(artist))>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE chart_publication (
    brand VARCHAR(2) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    snapshot_id BINARY(16) NULL,
    PRIMARY KEY (brand, period),
    CONSTRAINT ck_publication_brand CHECK (brand IN ('TJ','KY')),
    CONSTRAINT ck_publication_period CHECK (period IN ('DAILY','WEEKLY','MONTHLY')),
    CONSTRAINT fk_publication_snapshot FOREIGN KEY (brand, period, snapshot_id)
        REFERENCES chart_snapshot (brand, period, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
INSERT INTO chart_publication (brand,period) VALUES
    ('TJ','DAILY'),('TJ','WEEKLY'),('TJ','MONTHLY'),('KY','DAILY'),('KY','WEEKLY'),('KY','MONTHLY');

-- Logical reservation only: physical MySQL/index/log disk usage needs monitoring.
CREATE TABLE snapshot_capacity (
    id TINYINT NOT NULL,
    reserved_bytes BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT ck_snapshot_capacity_id CHECK (id=1),
    CONSTRAINT ck_snapshot_capacity_bytes CHECK (reserved_bytes BETWEEN 0 AND 1073741824)
) ENGINE=InnoDB;
INSERT INTO snapshot_capacity(id) VALUES(1);

CREATE TABLE snapshot_header (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    op_id BINARY(16) NOT NULL,
    purpose VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'BUILDING',
    schema_version INT NOT NULL,
    snapshot_cursor BIGINT NULL,
    captured_at DATETIME(3) NULL,
    ready_at DATETIME(3) NULL,
    expires_at DATETIME(3) NULL,
    row_count BIGINT NOT NULL DEFAULT 0,
    byte_count BIGINT NOT NULL DEFAULT 0,
    manifest_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    active_slot TINYINT NULL,
    reserved_bytes BIGINT NOT NULL,
    attempt_id BINARY(16) NOT NULL,
    attempt_count INT NOT NULL DEFAULT 1,
    build_started_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    lease_until DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_snapshot_owner_id (user_id,id),
    UNIQUE KEY uq_snapshot_owner_purpose (user_id,purpose,id),
    UNIQUE KEY uq_snapshot_attempt (id,attempt_id),
    UNIQUE KEY uq_snapshot_op (user_id,op_id),
    UNIQUE KEY uq_snapshot_slot (user_id,active_slot),
    KEY ix_snapshot_expiry (status,expires_at,id),
    KEY ix_snapshot_lease (status,lease_until,id),
    CONSTRAINT fk_snapshot_user FOREIGN KEY (user_id) REFERENCES app_user(id),
    CONSTRAINT ck_snapshot_purpose CHECK (purpose IN ('SYNC','EXPORT')),
    CONSTRAINT ck_snapshot_numbers CHECK (schema_version>0 AND attempt_count>0 AND row_count>=0
        AND byte_count>=0 AND reserved_bytes BETWEEN 0 AND 104857600 AND byte_count<=reserved_bytes),
    CONSTRAINT ck_snapshot_capture CHECK (
        (snapshot_cursor IS NULL AND captured_at IS NULL)
        OR (snapshot_cursor IS NOT NULL AND snapshot_cursor>=0 AND captured_at IS NOT NULL AND captured_at>=build_started_at)),
    CONSTRAINT ck_snapshot_hash CHECK (manifest_hash IS NULL OR manifest_hash REGEXP '^[0-9a-f]{64}$'),
    CONSTRAINT ck_snapshot_slot CHECK (
        (status IN ('BUILDING','READY') AND active_slot IS NOT NULL AND active_slot IN (0,1))
        OR (status IN ('EXPIRED','FAILED') AND active_slot IS NULL)),
    CONSTRAINT ck_snapshot_times CHECK (
        (status IN ('BUILDING','FAILED') AND ready_at IS NULL AND expires_at IS NULL AND manifest_hash IS NULL)
        OR (status IN ('READY','EXPIRED') AND ready_at IS NOT NULL AND captured_at IS NOT NULL
            AND ready_at>=captured_at AND ready_at<=build_started_at+INTERVAL 10 MINUTE
            AND expires_at IS NOT NULL AND expires_at=ready_at+INTERVAL 30 MINUTE AND manifest_hash IS NOT NULL)),
    CONSTRAINT ck_snapshot_lease CHECK (
        (status='BUILDING' AND lease_until IS NOT NULL AND lease_until>build_started_at
            AND lease_until<=build_started_at+INTERVAL 10 MINUTE)
        OR (status IN ('READY','EXPIRED','FAILED') AND lease_until IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE snapshot_entry (
    snapshot_id BINARY(16) NOT NULL,
    attempt_id BINARY(16) NOT NULL,
    entity VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    ordinal BIGINT NOT NULL,
    resource_id BINARY(16) NOT NULL,
    payload JSON NOT NULL,
    -- The storage hash/size use MySQL's normalized UTF-8 JSON text. API/ZIP
    -- canonical serialization and manifest hashing are P07/P21 responsibilities.
    payload_hash BINARY(32) GENERATED ALWAYS AS (UNHEX(SHA2(CAST(payload AS CHAR CHARACTER SET utf8mb4),256))) STORED,
    payload_bytes BIGINT GENERATED ALWAYS AS (OCTET_LENGTH(CAST(payload AS CHAR CHARACTER SET utf8mb4))) STORED,
    PRIMARY KEY (snapshot_id,entity,ordinal),
    CONSTRAINT fk_entry_attempt FOREIGN KEY (snapshot_id,attempt_id)
        REFERENCES snapshot_header(id,attempt_id) ON DELETE CASCADE,
    CONSTRAINT ck_snapshot_entry_ordinal CHECK (ordinal>0),
    CONSTRAINT ck_snapshot_entry_payload CHECK (JSON_TYPE(payload)='OBJECT'),
    CONSTRAINT ck_snapshot_entry_entity CHECK (entity IN (
        'SONG','SONG_SOURCE','RECORDING','RECORDING_FILE_SPEC','RECORDING_ASSET',
        'PLAYLIST','PLAYLIST_ITEM','TAG','RECORDING_TAG','RECORDING_CONDITION',
        'USER_ENTITLEMENT','STORAGE_USAGE','SONG_CLOUD_SELECTION','PIN_SLOT',
        'USER_SYNC_STATE','CHANGE_LOG','DELETION_BATCH','DELETION_ITEM','DELETION_LEDGER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE export_session (
    export_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    snapshot_id BINARY(16) NOT NULL,
    purpose VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'EXPORT',
    include_trash BOOLEAN NOT NULL,
    PRIMARY KEY (export_id),
    UNIQUE KEY uq_export_snapshot (snapshot_id),
    CONSTRAINT fk_export_snapshot FOREIGN KEY (user_id,purpose,snapshot_id)
        REFERENCES snapshot_header(user_id,purpose,id) ON DELETE CASCADE,
    CONSTRAINT ck_export_purpose CHECK (purpose='EXPORT'),
    CONSTRAINT ck_export_trash CHECK (include_trash IN (0,1))
) ENGINE=InnoDB;
-- Export state and TTL are authoritative in the header, not duplicate clocks.
CREATE VIEW export_session_state AS
    SELECT e.export_id,e.user_id,e.snapshot_id,e.include_trash,h.status,h.ready_at,h.expires_at
    FROM export_session e JOIN snapshot_header h ON h.id=e.snapshot_id;

DELIMITER $$
CREATE TRIGGER trg_chart_insert BEFORE INSERT ON chart_snapshot FOR EACH ROW
BEGIN
    IF NEW.state<>'STAGING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='New charts must be staged before publication';
    END IF;
END$$
CREATE TRIGGER trg_chart_update BEFORE UPDATE ON chart_snapshot FOR EACH ROW
BEGIN
    DECLARE actual_count INT;
    DECLARE last_position INT;
    IF OLD.state='PUBLISHED' OR NEW.id<>OLD.id OR NEW.brand<>OLD.brand OR NEW.period<>OLD.period
        OR NEW.revision<>OLD.revision OR NEW.source_url<>OLD.source_url OR NEW.fetched_at<>OLD.fetched_at THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Chart identity and published snapshots are immutable';
    END IF;
    IF NEW.state='PUBLISHED' THEN
        SELECT COUNT(*),MAX(position) INTO actual_count,last_position FROM chart_item WHERE snapshot_id=OLD.id FOR UPDATE;
        IF actual_count=0 OR actual_count<>NEW.item_count OR actual_count<>last_position THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publish only a nonempty contiguous complete chart';
        END IF;
    END IF;
END$$
CREATE TRIGGER trg_chart_item_insert BEFORE INSERT ON chart_item FOR EACH ROW
BEGIN
    DECLARE parent_state VARCHAR(16);
    SELECT state INTO parent_state FROM chart_snapshot WHERE id=NEW.snapshot_id FOR UPDATE;
    IF parent_state IS NULL OR parent_state<>'STAGING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Chart items require a staging snapshot';
    END IF;
END$$
CREATE TRIGGER trg_chart_item_update BEFORE UPDATE ON chart_item FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Replace staged chart rows instead of updating them';
END$$
CREATE TRIGGER trg_chart_item_delete BEFORE DELETE ON chart_item FOR EACH ROW
BEGIN
    DECLARE parent_state VARCHAR(16);
    SELECT state INTO parent_state FROM chart_snapshot WHERE id=OLD.snapshot_id FOR UPDATE;
    IF parent_state<>'STAGING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Published chart items are immutable';
    END IF;
END$$
CREATE TRIGGER trg_chart_publication_insert BEFORE INSERT ON chart_publication FOR EACH ROW
BEGIN
    IF NEW.snapshot_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Initialize the scope before publishing a chart';
    END IF;
END$$
CREATE TRIGGER trg_chart_publication_update BEFORE UPDATE ON chart_publication FOR EACH ROW
BEGIN
    DECLARE new_state VARCHAR(16);
    DECLARE new_revision BIGINT;
    DECLARE old_revision BIGINT DEFAULT 0;
    IF NEW.brand<>OLD.brand OR NEW.period<>OLD.period OR NEW.snapshot_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publication scope and last good result must be retained';
    END IF;
    SELECT state,revision INTO new_state,new_revision FROM chart_snapshot WHERE id=NEW.snapshot_id FOR SHARE;
    IF OLD.snapshot_id IS NOT NULL THEN
        SELECT revision INTO old_revision FROM chart_snapshot WHERE id=OLD.snapshot_id;
    END IF;
    IF new_state IS NULL OR new_state<>'PUBLISHED' OR new_revision<old_revision THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publication requires a verified nonregressing revision';
    END IF;
END$$

CREATE TRIGGER trg_snapshot_insert BEFORE INSERT ON snapshot_header FOR EACH ROW
BEGIN
    IF NEW.status<>'BUILDING' OR NEW.row_count<>0 OR NEW.byte_count<>0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='New snapshots must start with an empty building attempt';
    END IF;
    UPDATE snapshot_capacity SET reserved_bytes=reserved_bytes+NEW.reserved_bytes WHERE id=1;
    IF ROW_COUNT()=0 AND NEW.reserved_bytes<>0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Snapshot capacity row is missing';
    END IF;
END$$
CREATE TRIGGER trg_snapshot_update BEFORE UPDATE ON snapshot_header FOR EACH ROW
BEGIN
    DECLARE actual_rows BIGINT;
    DECLARE actual_bytes BIGINT;
    DECLARE gaps INT;
    IF NEW.id<>OLD.id OR NEW.user_id<>OLD.user_id OR NEW.op_id<>OLD.op_id OR NEW.purpose<>OLD.purpose
        OR NEW.schema_version<>OLD.schema_version OR NEW.created_at<>OLD.created_at THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Snapshot identity is immutable';
    END IF;
    IF OLD.status IN ('FAILED','EXPIRED') OR (OLD.status='READY' AND NEW.status NOT IN ('READY','EXPIRED'))
        OR (OLD.status='BUILDING' AND NEW.status NOT IN ('BUILDING','READY','FAILED')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid snapshot transition';
    END IF;
    IF OLD.status='READY' AND (NOT (NEW.snapshot_cursor<=>OLD.snapshot_cursor)
        OR NOT (NEW.captured_at<=>OLD.captured_at) OR NOT (NEW.ready_at<=>OLD.ready_at)
        OR NOT (NEW.expires_at<=>OLD.expires_at) OR NOT (NEW.manifest_hash<=>OLD.manifest_hash)
        OR NEW.row_count<>OLD.row_count OR NEW.byte_count<>OLD.byte_count
        OR NEW.attempt_id<>OLD.attempt_id OR NEW.attempt_count<>OLD.attempt_count
        OR NEW.build_started_at<>OLD.build_started_at) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ready snapshot contents and original expiry are immutable';
    END IF;
    IF OLD.status='BUILDING' THEN
        IF NEW.attempt_id<>OLD.attempt_id THEN
            IF NEW.status<>'BUILDING' OR NEW.attempt_count<>OLD.attempt_count+1
                OR NEW.snapshot_cursor IS NOT NULL OR NEW.captured_at IS NOT NULL
                OR NEW.row_count<>0 OR NEW.byte_count<>0
                OR EXISTS(SELECT 1 FROM snapshot_entry WHERE snapshot_id=OLD.id) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Discard the entire old attempt before restarting';
            END IF;
        ELSEIF NEW.attempt_count<>OLD.attempt_count OR NEW.build_started_at<>OLD.build_started_at
            OR (OLD.captured_at IS NOT NULL AND (NOT (NEW.captured_at<=>OLD.captured_at)
                OR NOT (NEW.snapshot_cursor<=>OLD.snapshot_cursor))) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Do not mix read views or extend the building deadline';
        END IF;
    END IF;
    IF NEW.status='READY' AND OLD.status='BUILDING' THEN
        SELECT COUNT(*),COALESCE(SUM(payload_bytes),0) INTO actual_rows,actual_bytes
            FROM snapshot_entry WHERE snapshot_id=OLD.id FOR UPDATE;
        SELECT COUNT(*) INTO gaps FROM (SELECT entity FROM snapshot_entry WHERE snapshot_id=OLD.id
            GROUP BY entity HAVING MIN(ordinal)<>1 OR MAX(ordinal)<>COUNT(*) FOR UPDATE) AS incomplete_entities;
        IF actual_rows<>NEW.row_count OR actual_bytes<>NEW.byte_count OR gaps<>0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Verify row counts bytes and entity ordinals before ready';
        END IF;
    END IF;
    IF NEW.reserved_bytes<>OLD.reserved_bytes THEN
        UPDATE snapshot_capacity SET reserved_bytes=reserved_bytes-OLD.reserved_bytes+NEW.reserved_bytes WHERE id=1;
    END IF;
END$$
CREATE TRIGGER trg_snapshot_delete BEFORE DELETE ON snapshot_header FOR EACH ROW
BEGIN
    IF OLD.status NOT IN ('EXPIRED','FAILED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalidate a snapshot before removing its stored rows';
    END IF;
    -- Expiration releases the user slot, not bytes that are still stored.
    -- Refund the remaining reservation atomically with physical row cleanup.
    UPDATE snapshot_capacity SET reserved_bytes=reserved_bytes-OLD.reserved_bytes WHERE id=1;
END$$
CREATE TRIGGER trg_snapshot_entry_insert BEFORE INSERT ON snapshot_entry FOR EACH ROW
BEGIN
    DECLARE parent_status VARCHAR(16);
    DECLARE parent_attempt BINARY(16);
    DECLARE reserved BIGINT;
    DECLARE used BIGINT;
    SELECT status,attempt_id,reserved_bytes,byte_count INTO parent_status,parent_attempt,reserved,used
        FROM snapshot_header WHERE id=NEW.snapshot_id FOR UPDATE;
    IF parent_status IS NULL OR parent_status<>'BUILDING' OR parent_attempt<>NEW.attempt_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Snapshot rows require the current building attempt';
    END IF;
    IF used+OCTET_LENGTH(CAST(NEW.payload AS CHAR CHARACTER SET utf8mb4))>reserved THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Reserve snapshot payload capacity before appending rows';
    END IF;
END$$
CREATE TRIGGER trg_snapshot_entry_insert_count AFTER INSERT ON snapshot_entry FOR EACH ROW
BEGIN
    UPDATE snapshot_header SET row_count=row_count+1,byte_count=byte_count+NEW.payload_bytes WHERE id=NEW.snapshot_id;
END$$
CREATE TRIGGER trg_snapshot_entry_update BEFORE UPDATE ON snapshot_entry FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Snapshot rows are append-only within a building attempt';
END$$
CREATE TRIGGER trg_snapshot_entry_delete BEFORE DELETE ON snapshot_entry FOR EACH ROW
BEGIN
    DECLARE parent_status VARCHAR(16);
    SELECT status INTO parent_status FROM snapshot_header WHERE id=OLD.snapshot_id FOR UPDATE;
    IF parent_status='READY' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ready snapshot rows cannot be changed';
    END IF;
END$$
CREATE TRIGGER trg_snapshot_entry_delete_count AFTER DELETE ON snapshot_entry FOR EACH ROW
BEGIN
    UPDATE snapshot_header SET row_count=row_count-1,byte_count=byte_count-OLD.payload_bytes
        WHERE id=OLD.snapshot_id AND status='BUILDING';
END$$
CREATE TRIGGER trg_export_update BEFORE UPDATE ON export_session FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Export snapshot identity and requested scope are immutable';
END$$
DELIMITER ;

-- P07 owns authentication, ACTIVE account checks, the single consistent source
-- read view, all-entity/manifest validation, and request-time expiration checks.
-- Lock snapshot_capacity before snapshot_header in reservation transactions;
-- reserve serialized bytes BEFORE writing partial entries. Trigger counters and
-- slot uniqueness serialize competing reservations, not arbitrary source reads.
-- P16 owns provider validation, source_token, collection and chart publication.
UPDATE app_schema_metadata SET schema_value='7' WHERE schema_key='schema_contract';
