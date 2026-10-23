-- USER-181: reactivate owned definitions without rewriting any recording or history.
DROP TRIGGER trg_recording_condition_before_insert;
DROP TRIGGER trg_recording_condition_before_update;
DELIMITER $$
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
        IF OLD.condition_code IS NOT NULL THEN
            INSERT INTO recording_condition_history(user_id,recording_id,source_revision,condition_code,condition_name_snapshot)
            SELECT OLD.user_id,OLD.id,OLD.revision,OLD.condition_code,OLD.condition_name_snapshot
            WHERE NOT EXISTS (SELECT 1 FROM recording_condition_history WHERE user_id=OLD.user_id AND recording_id=OLD.id AND source_revision=OLD.revision);
        END IF;
        SET NEW.condition_name_snapshot = NULL;
    ELSE
        IF OLD.condition_code IS NOT NULL THEN
            INSERT INTO recording_condition_history(user_id,recording_id,source_revision,condition_code,condition_name_snapshot)
            SELECT OLD.user_id,OLD.id,OLD.revision,OLD.condition_code,OLD.condition_name_snapshot
            WHERE NOT EXISTS (SELECT 1 FROM recording_condition_history WHERE user_id=OLD.user_id AND recording_id=OLD.id AND source_revision=OLD.revision);
        END IF;
        SELECT name,archived_at INTO current_name,archived FROM condition_definition
          WHERE user_id=NEW.user_id AND code=NEW.condition_code FOR SHARE;
        IF current_name IS NULL OR archived IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A new condition link requires an active owned condition';
        END IF;
        SET NEW.condition_name_snapshot = current_name;
    END IF;
END$$
DELIMITER ;
