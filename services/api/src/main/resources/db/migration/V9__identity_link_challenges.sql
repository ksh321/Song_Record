-- Session-bound, single-use challenges; provider tokens are never persisted.
CREATE TABLE auth_link_challenge (
    id BINARY(16) NOT NULL PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    stage VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_provider VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    nonce_hash BINARY(32) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    consumed_at DATETIME(3) NULL,
    CONSTRAINT fk_link_session FOREIGN KEY(session_id) REFERENCES auth_session(id) ON DELETE CASCADE,
    CONSTRAINT ck_link_stage CHECK(stage IN ('REAUTH','LINK')),
    CONSTRAINT ck_link_provider CHECK(provider IN ('GOOGLE','KAKAO') AND target_provider IN ('GOOGLE','KAKAO')),
    CONSTRAINT ck_link_expiry CHECK(expires_at > created_at),
    KEY ix_link_session(session_id),
    KEY ix_link_expiry(expires_at)
) ENGINE=InnoDB;
