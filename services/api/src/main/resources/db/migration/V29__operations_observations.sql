-- Strict projections only: no request/response bodies, notes, audio, URLs or authentication data.
CREATE TABLE operations_observation (
 id BINARY(16) PRIMARY KEY, actor_id BINARY(16) NULL, target_id BINARY(16) NULL,
 job_id BINARY(16) NULL, attempt_count INT NULL, previous_target_id BINARY(16) NULL, sync_change_backlog BIGINT NULL,
 actor_kind VARCHAR(16) NOT NULL, action VARCHAR(32) NOT NULL, result VARCHAR(32) NOT NULL,
 status_code INT NOT NULL, duration_ms BIGINT NOT NULL, observed_at DATETIME(3) NOT NULL,
 KEY ix_operations_actor_time(actor_id,observed_at,action),
 KEY ix_operations_action_time(action,observed_at,result),
 CONSTRAINT ck_operations_actor CHECK(actor_kind IN ('USER','WORKER','ANONYMOUS')),
 CONSTRAINT ck_operations_numbers CHECK(status_code BETWEEN 0 AND 599 AND duration_ms>=0)
) ENGINE=InnoDB;

-- Initiating authority is the owner of the durable mutation/slot, not an HTTP header.
-- Execution worker identity is separately recorded by JobQueue's committed lifecycle events.
DELIMITER $$
CREATE TRIGGER trg_operations_pin_replacement AFTER UPDATE ON pin_slot FOR EACH ROW
BEGIN
 DECLARE occupied_slots INT;
 SELECT COUNT(*) INTO occupied_slots FROM pin_slot WHERE user_id=NEW.user_id AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL);
 IF occupied_slots=10 THEN
  INSERT INTO operations_observation(id,actor_id,target_id,actor_kind,action,result,status_code,duration_ms,observed_at)
  VALUES(UUID_TO_BIN(UUID()),NEW.user_id,COALESCE(NEW.current_recording_id,NEW.pending_recording_id),'USER','PIN_SLOTS_TEN','SUCCESS',0,0,UTC_TIMESTAMP(3));
 END IF;
 IF OLD.current_recording_id IS NOT NULL AND NEW.current_recording_id IS NOT NULL
    AND OLD.current_recording_id<>NEW.current_recording_id THEN
  INSERT INTO operations_observation(id,actor_id,target_id,previous_target_id,actor_kind,action,result,status_code,duration_ms,observed_at)
  VALUES(UUID_TO_BIN(UUID()),NEW.user_id,NEW.current_recording_id,OLD.current_recording_id,'USER','PIN_REPLACE_COMMITTED','SUCCESS',0,0,UTC_TIMESTAMP(3));
 END IF;
END$$
CREATE TRIGGER trg_operations_pin_occupancy AFTER INSERT ON pin_slot FOR EACH ROW
BEGIN
 DECLARE occupied_slots INT;
 SELECT COUNT(*) INTO occupied_slots FROM pin_slot WHERE user_id=NEW.user_id AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL);
 IF occupied_slots=10 THEN
  INSERT INTO operations_observation(id,actor_id,target_id,actor_kind,action,result,status_code,duration_ms,observed_at)
  VALUES(UUID_TO_BIN(UUID()),NEW.user_id,COALESCE(NEW.current_recording_id,NEW.pending_recording_id),'USER','PIN_SLOTS_TEN','SUCCESS',0,0,UTC_TIMESTAMP(3));
 END IF;
END$$
CREATE TRIGGER trg_operations_permanent_deletion AFTER INSERT ON deletion_ledger FOR EACH ROW
BEGIN
 INSERT INTO operations_observation(id,actor_id,target_id,actor_kind,action,result,status_code,duration_ms,observed_at)
 VALUES(UUID_TO_BIN(UUID()),NEW.user_id,NEW.entity_id,'USER','DELETE_COMMITTED','SUCCESS',0,0,NEW.purged_at);
END$$
DELIMITER ;
