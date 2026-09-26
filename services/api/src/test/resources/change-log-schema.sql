-- user_sync_state already comes from registration-schema.sql.
CREATE TABLE change_log (
 user_id BINARY(16) NOT NULL,change_seq BIGINT NOT NULL,entity_type VARCHAR(64) NOT NULL,
 entity_id BINARY(16) NOT NULL,revision BIGINT NOT NULL,operation VARCHAR(16) NOT NULL,
 payload VARCHAR(1048576) NOT NULL,created_at TIMESTAMP(3) NOT NULL,expires_at TIMESTAMP(3) NOT NULL,
 PRIMARY KEY(user_id,change_seq),FOREIGN KEY(user_id) REFERENCES user_sync_state(user_id),
 CHECK(change_seq>0 AND revision>0),CHECK(operation IN ('UPSERT','DELETE'))
);
