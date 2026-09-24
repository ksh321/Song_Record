CREATE TABLE auth_session (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    device_id BINARY(16) NOT NULL,
    refresh_hash BINARY(32) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_auth_session_refresh_hash (refresh_hash),
    UNIQUE KEY uq_auth_session_owner_id (user_id, id),
    KEY ix_auth_session_owner_device (user_id, device_id, expires_at),
    CONSTRAINT fk_auth_session_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT fk_auth_session_device FOREIGN KEY (user_id, device_id)
        REFERENCES device (user_id, id),
    CONSTRAINT ck_auth_session_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_auth_session_revoked CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
-- Hash-only opaque tokens. Retain refresh history until its session expires or is deleted.
CREATE TABLE auth_refresh_token (
    token_hash BINARY(32) NOT NULL PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    consumed_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_refresh_session FOREIGN KEY (session_id) REFERENCES auth_session(id) ON DELETE CASCADE,
    KEY ix_refresh_session (session_id)
);
CREATE TABLE auth_access_token (
    token_hash BINARY(32) NOT NULL PRIMARY KEY,
    session_id BINARY(16) NOT NULL,
    expires_at DATETIME(3) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_access_session FOREIGN KEY (session_id) REFERENCES auth_session(id) ON DELETE CASCADE,
    CONSTRAINT ck_access_expiry CHECK (expires_at > created_at),
    KEY ix_access_session (session_id),
    KEY ix_access_expiry (expires_at)
);
-- Preserve current hashes for any pre-existing sessions; no raw token is available/needed.
INSERT INTO auth_refresh_token(token_hash,session_id,created_at)
SELECT refresh_hash,id,created_at FROM auth_session;
