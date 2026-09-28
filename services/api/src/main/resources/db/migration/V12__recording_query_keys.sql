-- Snapshot title keys; V13 fills existing rows before requests are served.
CREATE TABLE recording_query_key (
    recording_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    key_version VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    title_key VARBINARY(2048) NOT NULL,
    PRIMARY KEY (recording_id),
    KEY ix_recording_query_title (user_id, title_key, recording_id),
    CONSTRAINT fk_recording_query_owner FOREIGN KEY (user_id, recording_id) REFERENCES recording(user_id, id)
) ENGINE=InnoDB;
