-- USER-187: retain hidden deletion history while allowing a new visible candidate.
-- Identity derivation/owner checks in V4 remain unchanged.
ALTER TABLE playlist_item
    ADD COLUMN visible_entry_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin
        GENERATED ALWAYS AS (CASE WHEN hidden_by_batch_id IS NULL THEN entry_key ELSE NULL END) STORED,
    ADD COLUMN visible_song_id BINARY(16)
        GENERATED ALWAYS AS (CASE WHEN hidden_by_batch_id IS NULL THEN song_id ELSE NULL END) STORED,
    ADD UNIQUE KEY uq_playlist_visible_entry (playlist_id, visible_entry_key),
    ADD UNIQUE KEY uq_playlist_visible_song (playlist_id, visible_song_id),
    DROP INDEX uq_playlist_item_entry,
    DROP INDEX uq_playlist_item_song;
