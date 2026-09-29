-- Preserve every V15 definition and existing relationship. No rewrite or deletion.
CREATE TABLE recording_condition_history (
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    source_revision BIGINT NOT NULL,
    condition_code VARCHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    condition_name_snapshot VARCHAR(50) NOT NULL,
    PRIMARY KEY (user_id,recording_id,source_revision),
    CONSTRAINT fk_condition_history_recording FOREIGN KEY (user_id,recording_id)
        REFERENCES recording(user_id,id) ON DELETE CASCADE,
    CONSTRAINT ck_condition_history_revision CHECK (source_revision > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO recording_condition_history(user_id,recording_id,source_revision,condition_code,condition_name_snapshot)
SELECT user_id,id,revision,condition_code,condition_name_snapshot FROM recording WHERE condition_code IS NOT NULL;

DROP TRIGGER trg_recording_condition_before_insert;
DROP TRIGGER trg_recording_condition_before_update;
DELIMITER $$
-- Historical identity and snapshot are append-only. Recording purge still owns cleanup.
CREATE TRIGGER trg_condition_history_before_update BEFORE UPDATE ON recording_condition_history FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition history is immutable';
END$$
-- InnoDB cascades do not invoke this trigger; owning-recording cleanup remains possible.
CREATE TRIGGER trg_condition_history_before_delete BEFORE DELETE ON recording_condition_history FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Condition history cannot be deleted independently';
END$$
CREATE TRIGGER trg_recording_condition_before_insert BEFORE INSERT ON recording FOR EACH ROW
BEGIN
    DECLARE fixed_name VARCHAR(50) DEFAULT NULL;
    IF NEW.condition_code IS NULL THEN
        SET NEW.condition_name_snapshot = NULL;
    ELSE
        SELECT name INTO fixed_name FROM condition_catalog WHERE code=NEW.condition_code;
        IF fixed_name IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New selections require the fixed condition catalog';
        END IF;
        SET NEW.condition_name_snapshot = fixed_name;
    END IF;
END$$
CREATE TRIGGER trg_recording_condition_before_update BEFORE UPDATE ON recording FOR EACH ROW
BEGIN
    DECLARE fixed_name VARCHAR(50) DEFAULT NULL;
    IF NEW.user_id <> OLD.user_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Recording owner is immutable';
    END IF;
    IF NEW.condition_code <=> OLD.condition_code THEN
        SET NEW.condition_name_snapshot = OLD.condition_name_snapshot;
    ELSE
        IF NEW.condition_code IS NOT NULL THEN
            SELECT name INTO fixed_name FROM condition_catalog WHERE code=NEW.condition_code;
            IF fixed_name IS NULL THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New selections require the fixed condition catalog';
            END IF;
        END IF;
        IF OLD.condition_code IS NOT NULL THEN
            INSERT INTO recording_condition_history(user_id,recording_id,source_revision,condition_code,condition_name_snapshot)
            SELECT OLD.user_id,OLD.id,OLD.revision,OLD.condition_code,OLD.condition_name_snapshot
            WHERE NOT EXISTS (SELECT 1 FROM recording_condition_history WHERE user_id=OLD.user_id AND recording_id=OLD.id AND source_revision=OLD.revision);
        END IF;
        SET NEW.condition_name_snapshot = fixed_name;
    END IF;
END$$
DELIMITER ;
