CREATE TABLE deletion_web_challenge (
 id BINARY(16) PRIMARY KEY, provider VARCHAR(16) NOT NULL,
 nonce_hash BINARY(32) NOT NULL, state_hash BINARY(32) NOT NULL,
 requester_hash BINARY(32) NOT NULL, created_at DATETIME(3) NOT NULL,
 expires_at DATETIME(3) NOT NULL, consumed_at DATETIME(3) NULL,
 KEY ix_deletion_web_rate(requester_hash,created_at),
 UNIQUE KEY uq_deletion_web_state(state_hash),
 CONSTRAINT ck_deletion_web_provider CHECK(provider IN ('GOOGLE','KAKAO'))
) ENGINE=InnoDB;
CREATE TABLE deletion_web_rate (
 requester_hash BINARY(32) PRIMARY KEY, window_at DATETIME(3) NOT NULL,
 request_count INT NOT NULL
) ENGINE=InnoDB;
