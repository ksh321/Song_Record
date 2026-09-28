-- Derived search/sort keys. V11 fills existing songs before the API starts.
CREATE TABLE song_query_key (
    song_id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    key_version VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    title_key VARBINARY(2048) NOT NULL,
    artist_key VARBINARY(2048) NOT NULL,
    title_search VARBINARY(2400) NOT NULL,
    artist_search VARBINARY(2400) NOT NULL,
    PRIMARY KEY (song_id),
    KEY ix_song_query_title (user_id, title_key, song_id),
    KEY ix_song_query_artist (user_id, artist_key, song_id),
    CONSTRAINT fk_song_query_owner FOREIGN KEY (user_id, song_id) REFERENCES song(user_id, id)
) ENGINE=InnoDB;

CREATE INDEX ix_song_owner_added ON song(user_id, lifecycle_state, created_at, id);
CREATE INDEX ix_recording_song_latest ON recording(user_id, song_id, lifecycle_state, metadata_state, recorded_at);
