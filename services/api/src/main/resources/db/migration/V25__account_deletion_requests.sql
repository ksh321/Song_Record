ALTER TABLE app_user ADD COLUMN revision BIGINT NOT NULL DEFAULT 1;
CREATE TABLE account_deletion_challenge (
 id BINARY(16) PRIMARY KEY, user_id BINARY(16) NOT NULL, session_id BINARY(16) NOT NULL,
 provider VARCHAR(16) NOT NULL, nonce_hash BINARY(32) NOT NULL,
 created_at DATETIME(3) NOT NULL, expires_at DATETIME(3) NOT NULL,
 verified_at DATETIME(3) NULL,
 KEY ix_deletion_challenge_owner(user_id,created_at),
 CONSTRAINT fk_deletion_challenge_owner FOREIGN KEY(user_id) REFERENCES app_user(id)
) ENGINE=InnoDB;
CREATE TABLE account_deletion_status (
 id BINARY(16) PRIMARY KEY, user_id BINARY(16) NULL, session_id BINARY(16) NOT NULL,
 challenge_id BINARY(16) NOT NULL, token_hash BINARY(32) NOT NULL,
 state VARCHAR(32) NOT NULL DEFAULT 'PREPARED',
 prepared_at DATETIME(3) NOT NULL, prepare_expires_at DATETIME(3) NOT NULL,
 accepted_at DATETIME(3) NULL, expires_at DATETIME(3) NULL,
 service_deleted_at DATETIME(3) NULL, backup_purge_due_at DATETIME(3) NULL,
 completed_at DATETIME(3) NULL, retrying BOOLEAN NOT NULL DEFAULT FALSE,
 operation_id BINARY(16) NULL, request_hash CHAR(64) NULL,
 query_window_at DATETIME(3) NULL, query_count INT NOT NULL DEFAULT 0,
 UNIQUE KEY uq_deletion_challenge_preparation(challenge_id),
 UNIQUE KEY uq_deletion_operation(user_id,operation_id),
 KEY ix_deletion_status_owner(user_id,state),
 CONSTRAINT ck_deletion_status CHECK(state IN ('PREPARED','ACCEPTED','DELETING','BACKUP_CLEANUP','COMPLETED'))
) ENGINE=InnoDB;
