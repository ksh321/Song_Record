-- P12-11 observations never overwrite the operator's budget lock or silently repair usage.
ALTER TABLE global_storage_usage
 ADD COLUMN reconciliation_locked BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN final_observed_bytes BIGINT NOT NULL DEFAULT 0,
 ADD COLUMN reconciliation_issue_count BIGINT NOT NULL DEFAULT 0,
 ADD COLUMN reconciliation_at DATETIME(3) NULL,
 ADD CONSTRAINT ck_inventory_numbers CHECK(final_observed_bytes>=0 AND reconciliation_issue_count>=0 AND reconciliation_locked IN (0,1));
