-- Minimal deletion control survives personal database cleanup; no live-user FK.
ALTER TABLE account_deletion_status MODIFY session_id BINARY(16) NULL, MODIFY challenge_id BINARY(16) NULL;
CREATE TABLE account_deletion_work (
 preparation_id BINARY(16) PRIMARY KEY, owner_id BINARY(16) NOT NULL,
 accepted_at DATETIME(3) NOT NULL, owner_revision BIGINT NOT NULL,
 drain_until DATETIME(3) NULL, service_deleted_at DATETIME(3) NULL,
 backup_confirmed_at DATETIME(3) NULL, failure_count INT NOT NULL DEFAULT 0,
 last_error VARCHAR(64) NULL, updated_at DATETIME(3) NOT NULL,
 UNIQUE KEY uq_deletion_work_owner(owner_id),
 CONSTRAINT ck_deletion_work_failure CHECK(failure_count>=0 AND owner_revision>0)
) ENGINE=InnoDB;
INSERT INTO account_deletion_work(preparation_id,owner_id,accepted_at,owner_revision,service_deleted_at,backup_confirmed_at,updated_at)
SELECT s.id,s.user_id,s.accepted_at,l.revision,s.service_deleted_at,s.completed_at,UTC_TIMESTAMP(3)
FROM account_deletion_status s JOIN deletion_ledger l ON l.user_id=s.user_id AND l.entity_type='USER' AND l.entity_id=s.user_id
WHERE s.accepted_at IS NOT NULL AND s.user_id IS NOT NULL;
CREATE TABLE account_deletion_device_proof (
 token_hash BINARY(32) PRIMARY KEY, owner_id BINARY(16) NOT NULL,
 device_id BINARY(16) NOT NULL, expires_at DATETIME(3) NOT NULL,
 KEY ix_deletion_device_owner(owner_id), KEY ix_deletion_device_expiry(expires_at)
) ENGINE=InnoDB;
INSERT INTO account_deletion_device_proof(token_hash,owner_id,device_id,expires_at)
SELECT t.token_hash,s.user_id,s.device_id,w.accepted_at+INTERVAL 30 DAY
FROM auth_refresh_token t JOIN auth_session s ON s.id=t.session_id JOIN account_deletion_work w ON w.owner_id=s.user_id;
