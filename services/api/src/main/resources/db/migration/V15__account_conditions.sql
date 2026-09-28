-- Keep legacy recording codes and historical names intact. Each account owns its definitions.
CREATE TABLE condition_definition (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    code VARCHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    name VARCHAR(50) NOT NULL,
    normalized_name_key VARBINARY(800) NOT NULL,
    active_name_key VARBINARY(800) GENERATED ALWAYS AS (
        CASE WHEN archived_at IS NULL THEN normalized_name_key ELSE NULL END
    ) STORED,
    archived_at DATETIME(3) NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_condition_owner_id (user_id,id),
    UNIQUE KEY uq_condition_owner_code (user_id,code),
    UNIQUE KEY uq_condition_owner_active_name (user_id,active_name_key),
    CONSTRAINT fk_condition_owner FOREIGN KEY (user_id) REFERENCES app_user(id),
    CONSTRAINT ck_condition_name CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 50),
    CONSTRAINT ck_condition_key CHECK (OCTET_LENGTH(normalized_name_key) BETWEEN 1 AND 800),
    CONSTRAINT ck_condition_revision CHECK (revision > 0),
    CONSTRAINT ck_condition_identity CHECK (
        code IN ('VERY_GOOD','GOOD','NORMAL','BAD') OR (CHAR_LENGTH(code)=36 AND REPLACE(code,'-','')=LOWER(HEX(id)))
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Catalog names are fixed NFC Korean strings. Binary UTF-8 is their normalization key.
INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key)
SELECT UNHEX(MD5(CONCAT('songrecord:condition:',HEX(u.id),':',c.code))),u.id,c.code,c.name,CONVERT(c.name USING binary)
FROM app_user u CROSS JOIN condition_catalog c;

DROP TRIGGER trg_recording_condition_before_insert;
DROP TRIGGER trg_recording_condition_before_update;
ALTER TABLE recording DROP FOREIGN KEY fk_recording_condition;
ALTER TABLE recording MODIFY condition_code VARCHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL;
ALTER TABLE recording ADD CONSTRAINT fk_recording_owned_condition FOREIGN KEY(user_id,condition_code)
    REFERENCES condition_definition(user_id,code);
ALTER TABLE deletion_ledger DROP CHECK ck_ledger_type;
ALTER TABLE deletion_ledger ADD CONSTRAINT ck_ledger_type CHECK (
    entity_type IN ('USER','SONG','RECORDING','PLAYLIST','PLAYLIST_ITEM','TAG','CONDITION','RECORDING_ASSET')
);

DELIMITER $$
CREATE TRIGGER trg_user_default_conditions AFTER INSERT ON app_user FOR EACH ROW
BEGIN
    INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key)
    SELECT UNHEX(MD5(CONCAT('songrecord:condition:',HEX(NEW.id),':',c.code))),NEW.id,c.code,c.name,CONVERT(c.name USING binary)
    FROM condition_catalog c;
END$$
CREATE TRIGGER trg_condition_identity_before_update BEFORE UPDATE ON condition_definition FOR EACH ROW
BEGIN
    IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id OR BINARY NEW.code <> BINARY OLD.code THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition identity and owner are immutable';
    END IF;
END$$
CREATE TRIGGER trg_recording_condition_before_insert BEFORE INSERT ON recording FOR EACH ROW
BEGIN
    DECLARE current_name VARCHAR(50) DEFAULT NULL;
    DECLARE archived DATETIME(3);
    IF NEW.condition_code IS NULL THEN
        SET NEW.condition_name_snapshot = NULL;
    ELSE
        SELECT name,archived_at INTO current_name,archived FROM condition_definition
          WHERE user_id=NEW.user_id AND code=NEW.condition_code FOR SHARE;
        IF current_name IS NULL OR archived IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A new condition link requires an active owned condition';
        END IF;
        SET NEW.condition_name_snapshot = current_name;
    END IF;
END$$
CREATE TRIGGER trg_recording_condition_before_update BEFORE UPDATE ON recording FOR EACH ROW
BEGIN
    DECLARE current_name VARCHAR(50) DEFAULT NULL;
    DECLARE archived DATETIME(3);
    IF NEW.user_id <> OLD.user_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Recording owner is immutable';
    END IF;
    IF NEW.condition_code <=> OLD.condition_code THEN
        SET NEW.condition_name_snapshot = OLD.condition_name_snapshot;
    ELSEIF NEW.condition_code IS NULL THEN
        SET NEW.condition_name_snapshot = NULL;
    ELSE
        SELECT name,archived_at INTO current_name,archived FROM condition_definition
          WHERE user_id=NEW.user_id AND code=NEW.condition_code FOR SHARE;
        IF current_name IS NULL OR archived IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A new condition link requires an active owned condition';
        END IF;
        SET NEW.condition_name_snapshot = current_name;
    END IF;
END$$
DELIMITER ;
