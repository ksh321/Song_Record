-- One history row per accepted revision, in the same transaction as the metadata edit.
CREATE TABLE recording_time_correction (
    user_id BINARY(16) NOT NULL,
    recording_id BINARY(16) NOT NULL,
    revision BIGINT NOT NULL,
    actor_device_id BINARY(16) NOT NULL,
    old_recorded_at DATETIME(3) NOT NULL,
    new_recorded_at DATETIME(3) NOT NULL,
    old_timezone_id VARCHAR(64) NOT NULL,
    new_timezone_id VARCHAR(64) NOT NULL,
    old_offset_minutes SMALLINT NOT NULL,
    new_offset_minutes SMALLINT NOT NULL,
    corrected_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (recording_id, revision),
    KEY ix_recording_time_correction_owner (user_id, recording_id, revision),
    CONSTRAINT fk_time_correction_recording FOREIGN KEY (user_id, recording_id) REFERENCES recording(user_id, id),
    CONSTRAINT fk_time_correction_device FOREIGN KEY (user_id, actor_device_id) REFERENCES device(user_id, id),
    CONSTRAINT ck_time_correction_revision CHECK (revision > 1),
    CONSTRAINT ck_time_correction_offset CHECK (old_offset_minutes BETWEEN -1080 AND 1080 AND new_offset_minutes BETWEEN -1080 AND 1080)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
