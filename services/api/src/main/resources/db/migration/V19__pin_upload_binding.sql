-- Bind failure cleanup to the exact pending pin request, not just a recording UUID.
-- No receipt FK: request receipts expire while upload history remains.
ALTER TABLE recording_upload ADD COLUMN pin_operation_id BINARY(16) NULL;
DELIMITER $$
CREATE TRIGGER trg_upload_pin_binding_before_update BEFORE UPDATE ON recording_upload FOR EACH ROW
BEGIN
 IF NOT (NEW.pin_operation_id <=> OLD.pin_operation_id) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Captured pin operation is immutable';
 END IF;
END$$
DELIMITER ;
