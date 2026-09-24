-- H2 test fixture projected from V2/V5/V6. Production migrations remain MySQL-only.
CREATE TABLE app_user (
    id BINARY(16) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    CONSTRAINT ck_app_user_status CHECK (status IN ('ACTIVE', 'DELETING'))
);

CREATE TABLE device (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    display_name VARCHAR(200) NOT NULL,
    last_seen_at DATETIME(3) NOT NULL,
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_device_owner_id (user_id, id),
    KEY ix_device_owner_seen (user_id, last_seen_at, id),
    CONSTRAINT fk_device_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_device_name_length CHECK (CHAR_LENGTH(display_name) BETWEEN 1 AND 200)
);

CREATE TABLE auth_identity (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    provider VARCHAR(16) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    email VARCHAR(320) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_auth_identity_provider_user (provider, provider_user_id),
    UNIQUE KEY uq_auth_identity_owner_id (user_id, id),
    KEY ix_auth_identity_owner (user_id, id),
    CONSTRAINT fk_auth_identity_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_auth_identity_provider CHECK (provider IN ('GOOGLE', 'KAKAO')),
    CONSTRAINT ck_auth_identity_provider_user CHECK (CHAR_LENGTH(provider_user_id) BETWEEN 1 AND 255)
);

CREATE TABLE user_entitlement (
    user_id BINARY(16) NOT NULL,
    plan_code VARCHAR(16) NOT NULL DEFAULT 'FREE',
    pinned_limit INT NOT NULL DEFAULT 10,
    quota_bytes BIGINT NOT NULL DEFAULT 1000000000,
    revision BIGINT NOT NULL DEFAULT 1,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_entitlement_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_user_entitlement_plan CHECK (plan_code = 'FREE'),
    CONSTRAINT ck_user_entitlement_limits CHECK (
        pinned_limit >= 0 AND quota_bytes >= 0 AND revision > 0
    )
);

CREATE TABLE storage_usage (
    user_id BINARY(16) NOT NULL,
    used_bytes BIGINT NOT NULL DEFAULT 0,
    reserved_bytes BIGINT NOT NULL DEFAULT 0,
    revision BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_storage_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_storage_numbers CHECK (used_bytes >= 0 AND reserved_bytes >= 0 AND revision > 0)
);

CREATE TABLE user_sync_state (
    user_id BINARY(16) NOT NULL,
    last_change_seq BIGINT NOT NULL DEFAULT 0,
    retained_from_seq BIGINT NOT NULL DEFAULT 1,
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id),
    CONSTRAINT fk_sync_user FOREIGN KEY (user_id) REFERENCES app_user (id),
    CONSTRAINT ck_sync_sequences CHECK (last_change_seq >= 0 AND retained_from_seq > 0
        AND retained_from_seq - 1 <= last_change_seq)
);
