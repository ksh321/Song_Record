-- D08: request bodies expire after 90 days. Minimal IDs prevent recounting.
CREATE TABLE storage_request_ledger (
 id BINARY(16) PRIMARY KEY, user_id BINARY(16) NOT NULL,
 received_at DATETIME(3) NOT NULL,
 UNIQUE KEY uq_storage_request_owner(user_id,id),
 KEY ix_storage_request_period(user_id,received_at,id),
 CONSTRAINT fk_storage_request_owner FOREIGN KEY(user_id) REFERENCES app_user(id)
) ENGINE=InnoDB;
-- Short-lived index of common receipts belonging to this 90-day request body.
CREATE TABLE storage_request_operation (
 user_id BINARY(16) NOT NULL, op_id BINARY(16) NOT NULL,
 request_id BINARY(16) NOT NULL, received_at DATETIME(3) NOT NULL,
 PRIMARY KEY(user_id,op_id), KEY ix_storage_request_operation_expiry(received_at),
 CONSTRAINT fk_storage_request_operation FOREIGN KEY(user_id,request_id) REFERENCES storage_request_ledger(user_id,id)
) ENGINE=InnoDB;
CREATE TABLE storage_request_body (
 id BINARY(16) PRIMARY KEY, user_id BINARY(16) NOT NULL,
 pin_limit BOOLEAN NOT NULL, storage_quota BOOLEAN NOT NULL,
 received_at DATETIME(3) NOT NULL, revision BIGINT NOT NULL DEFAULT 1,
 pinned_used INT NOT NULL, pinned_limit INT NOT NULL,
 used_bytes BIGINT NOT NULL, quota_bytes BIGINT NOT NULL,
 KEY ix_storage_request_recent(user_id,received_at,id),
 CONSTRAINT fk_storage_request_id FOREIGN KEY(user_id,id) REFERENCES storage_request_ledger(user_id,id),
 CONSTRAINT ck_storage_request_types CHECK(pin_limit + storage_quota BETWEEN 1 AND 2),
 CONSTRAINT ck_storage_request_snapshot CHECK(revision=1 AND pinned_used>=0 AND pinned_limit>=0 AND used_bytes>=0 AND quota_bytes>=0)
) ENGINE=InnoDB;
-- Daily UTC aggregates contain no user IDs, request IDs, or individual usage.
CREATE TABLE storage_request_daily (
 period_date DATE PRIMARY KEY,
 request_total BIGINT UNSIGNED NOT NULL, pin_requests BIGINT UNSIGNED NOT NULL,
 quota_requests BIGINT UNSIGNED NOT NULL, unique_users BIGINT UNSIGNED NOT NULL,
 CONSTRAINT ck_storage_request_counts CHECK(pin_requests<=request_total AND quota_requests<=request_total AND unique_users<=request_total)
) ENGINE=InnoDB;
