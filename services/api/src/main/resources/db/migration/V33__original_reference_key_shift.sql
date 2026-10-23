-- User-confirmed meaning: ORIGINAL is the original-song reference, and shift
-- records a semitone offset from that reference. Existing values stay intact.
ALTER TABLE song DROP CHECK ck_song_representative_key,
    ADD CONSTRAINT ck_song_representative_key CHECK (
        (representative_key_mode IS NULL AND representative_key_shift IS NULL)
        OR (representative_key_mode IS NOT NULL AND representative_key_shift IS NOT NULL
            AND representative_key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND representative_key_shift BETWEEN -12 AND 12)
    );

ALTER TABLE recording DROP CHECK ck_recording_key,
    ADD CONSTRAINT ck_recording_key CHECK (
        (key_mode IS NULL AND key_shift IS NULL)
        OR (key_mode IS NOT NULL AND key_shift IS NOT NULL
            AND key_mode IN ('ORIGINAL', 'MALE', 'FEMALE')
            AND key_shift BETWEEN -12 AND 12)
    );
