CREATE TABLE job (
 id BINARY(16) PRIMARY KEY,user_id BINARY(16),type VARCHAR(64) NOT NULL,aggregate_id BINARY(16) NOT NULL,
 dedupe_key VARBINARY(255) UNIQUE NOT NULL,payload VARCHAR(1048576) NOT NULL,
 state VARCHAR(16) NOT NULL DEFAULT 'QUEUED',attempt_count INT NOT NULL DEFAULT 0,
 run_after TIMESTAMP(3) NOT NULL,lease_token BINARY(16),claimed_at TIMESTAMP(3),lease_until TIMESTAMP(3),
 last_error VARCHAR(512),finished_at TIMESTAMP(3),revision BIGINT DEFAULT 1,
 created_at TIMESTAMP(3) NOT NULL,updated_at TIMESTAMP(3) NOT NULL,
 CHECK(state IN ('QUEUED','RUNNING','RETRY_WAIT','SUCCEEDED','FAILED','CANCELLED')),
 CHECK((state='RUNNING' AND lease_token IS NOT NULL AND claimed_at IS NOT NULL AND lease_until>claimed_at AND attempt_count>0)
 OR (state<>'RUNNING' AND lease_token IS NULL AND claimed_at IS NULL AND lease_until IS NULL)),
 CHECK((state IN ('SUCCEEDED','FAILED','CANCELLED') AND finished_at IS NOT NULL) OR (state NOT IN ('SUCCEEDED','FAILED','CANCELLED') AND finished_at IS NULL))
);
