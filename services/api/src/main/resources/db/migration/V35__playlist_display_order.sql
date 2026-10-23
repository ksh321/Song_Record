ALTER TABLE playlist ADD COLUMN display_order BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT ck_playlist_display_order CHECK (display_order >= 0);
