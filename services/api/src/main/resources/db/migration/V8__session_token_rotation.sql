-- Hash-only opaque tokens. Retain refresh history until its session expires or is deleted.
CREATE TABLE auth_refresh_token (
    token_hash BINARY(32) NOT NULL PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    consumed_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_refresh_session FOREIGN KEY (session_id) REFERENCES auth_session(id) ON DELETE CASCADE,
    KEY ix_refresh_session (session_id)
) ENGINE=InnoDB;
CREATE TABLE auth_access_token (
    token_hash BINARY(32) NOT NULL PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_access_session FOREIGN KEY (session_id) REFERENCES auth_session(id) ON DELETE CASCADE,
    CONSTRAINT ck_access_expiry CHECK (expires_at > created_at),
    KEY ix_access_session (session_id),
    KEY ix_access_expiry (expires_at)
) ENGINE=InnoDB;
-- Preserve current hashes for any pre-existing sessions; no raw token is available/needed.
INSERT INTO auth_refresh_token(token_hash,session_id,created_at)
SELECT refresh_hash,id,created_at FROM auth_session;
