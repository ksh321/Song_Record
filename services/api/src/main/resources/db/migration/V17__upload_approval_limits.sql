CREATE TABLE upload_approval_daily (
    user_id BINARY(16) NOT NULL,
    utc_day DATE NOT NULL,
    approved_bytes BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, utc_day),
    CONSTRAINT fk_upload_daily_user FOREIGN KEY (user_id) REFERENCES app_user(id),
    CONSTRAINT ck_upload_daily_bytes CHECK (approved_bytes BETWEEN 0 AND 104857600)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE upload_url_issue (
    user_id BINARY(16) NOT NULL,
    id BINARY(16) NOT NULL,
    issued_at DATETIME(3) NOT NULL,
    PRIMARY KEY (user_id,id),
    KEY ix_upload_url_window (user_id,issued_at),
    CONSTRAINT fk_upload_url_user FOREIGN KEY (user_id) REFERENCES app_user(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
