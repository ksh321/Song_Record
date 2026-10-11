-- The original deletion snapshot/expiry remains immutable (V6 trigger).
-- Optimistic command version is separate from that historical evidence.
CREATE TABLE deletion_batch_work (
    user_id BINARY(16) NOT NULL,
    batch_id BINARY(16) NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id,batch_id),
    CONSTRAINT fk_batch_work_snapshot FOREIGN KEY (user_id,batch_id) REFERENCES deletion_batch(user_id,id),
    CONSTRAINT ck_batch_work_revision CHECK (revision > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
INSERT INTO deletion_batch_work(user_id,batch_id) SELECT user_id,id FROM deletion_batch;
