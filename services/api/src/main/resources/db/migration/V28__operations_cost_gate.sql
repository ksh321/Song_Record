ALTER TABLE global_storage_usage
    ADD COLUMN cost_monitor_required BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN cost_upload_locked BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN cost_observed_at DATETIME(3) NULL,
    ADD COLUMN cost_monthly_estimate_krw BIGINT NULL;
