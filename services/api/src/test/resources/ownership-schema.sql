-- Minimal ownership projection of V3/V4; intentionally omit FKs to test defensive joins.
CREATE TABLE song(id BINARY(16) PRIMARY KEY,user_id BINARY(16),lifecycle_state VARCHAR(20));
CREATE TABLE recording(id BINARY(16) PRIMARY KEY,user_id BINARY(16),song_id BINARY(16));
CREATE TABLE playlist(id BINARY(16) PRIMARY KEY,user_id BINARY(16));
CREATE TABLE tag(id BINARY(16) PRIMARY KEY,user_id BINARY(16));
CREATE TABLE playlist_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),playlist_id BINARY(16),song_id BINARY(16));
CREATE TABLE recording_tag(user_id BINARY(16),recording_id BINARY(16),tag_id BINARY(16));
CREATE TABLE recording_asset(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16));
CREATE TABLE recording_upload(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16));
