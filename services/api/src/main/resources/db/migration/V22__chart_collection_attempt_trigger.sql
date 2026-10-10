-- Retain V7 last-good/publication/revision protection while allowing metadata-only collection starts.
DROP TRIGGER trg_chart_publication_update;
DELIMITER $$
CREATE TRIGGER trg_chart_publication_update BEFORE UPDATE ON chart_publication FOR EACH ROW
BEGIN
    DECLARE new_state VARCHAR(16);
    DECLARE new_revision BIGINT;
    DECLARE old_revision BIGINT DEFAULT 0;
    IF NEW.brand<>OLD.brand OR NEW.period<>OLD.period THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publication scope must be retained';
    END IF;
    IF NEW.snapshot_id <=> OLD.snapshot_id THEN
        IF NOT (NEW.published_attempt_id <=> OLD.published_attempt_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Collection metadata cannot refresh a previous snapshot';
        END IF;
    ELSE
        IF NEW.snapshot_id IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Last good result must be retained';
        END IF;
        SELECT state,revision INTO new_state,new_revision FROM chart_snapshot WHERE id=NEW.snapshot_id FOR SHARE;
        IF OLD.snapshot_id IS NOT NULL THEN
            SELECT revision INTO old_revision FROM chart_snapshot WHERE id=OLD.snapshot_id;
        END IF;
        IF new_state IS NULL OR new_state<>'PUBLISHED' OR new_revision<old_revision THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publication requires a verified nonregressing revision';
        END IF;
        IF NEW.collection_attempt_id IS NULL OR NOT (NEW.published_attempt_id <=> NEW.collection_attempt_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Publish only the current collection attempt';
        END IF;
    END IF;
END$$
DELIMITER ;
