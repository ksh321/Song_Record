package com.ksh321.songrecord.api.domain;

import java.time.Instant;
import java.util.Objects;

public final class RecordingModels {
    private RecordingModels() {}

    public record RecordingSnapshot(
            DomainTypes.RecordingId id,
            DomainTypes.SongId songId,
            String title,
            String artist,
            DomainTypes.MusicalKey key,
            DomainTypes.VersionCode version,
            String note,
            Instant recordedAt,
            String timezoneId,
            int timezoneOffsetMinutes) {
        public RecordingSnapshot {
            Objects.requireNonNull(id, "id");
            Objects.requireNonNull(title, "title");
            Objects.requireNonNull(artist, "artist");
            Objects.requireNonNull(key, "key");
            Objects.requireNonNull(version, "version");
            Objects.requireNonNull(note, "note");
            Objects.requireNonNull(recordedAt, "recordedAt");
            Objects.requireNonNull(timezoneId, "timezoneId");
            if (title.isEmpty() || artist.isEmpty()) {
                throw new IllegalArgumentException("저장 완료된 녹음의 곡명과 가수는 필수입니다.");
            }
            if (timezoneOffsetMinutes < -1080 || timezoneOffsetMinutes > 1080) {
                throw new IllegalArgumentException("시간대 오프셋 범위가 올바르지 않습니다.");
            }
        }

        public RecordingSnapshot relink(DomainTypes.SongId nextSongId) {
            return new RecordingSnapshot(id, nextSongId, title, artist, key, version, note,
                    recordedAt, timezoneId, timezoneOffsetMinutes);
        }
    }

    public record SongDefaults(
            DomainTypes.SongId songId,
            DomainTypes.VersionCode version,
            DomainTypes.MusicalKey representativeKey) {
        public SongDefaults {
            Objects.requireNonNull(songId, "songId");
            Objects.requireNonNull(version, "version");
        }
    }

    public record RecordingDefaultState(
            DomainTypes.SongId songId,
            DomainTypes.MusicalKey key,
            DomainTypes.VersionCode version,
            boolean keyEdited,
            boolean versionEdited) {
        public RecordingDefaultState {
            Objects.requireNonNull(key, "key");
            Objects.requireNonNull(version, "version");
        }

        public static RecordingDefaultState initial() {
            return new RecordingDefaultState(null, DomainTypes.MusicalKey.original(),
                    DomainTypes.VersionCode.NORMAL, false, false);
        }

        public RecordingDefaultState selectSong(SongDefaults song) {
            return new RecordingDefaultState(
                    song.songId,
                    keyEdited ? key : defaultKey(song),
                    versionEdited ? version : song.version,
                    keyEdited,
                    versionEdited);
        }

        public RecordingDefaultState editKey(DomainTypes.MusicalKey value) {
            return new RecordingDefaultState(songId, value, version, true, versionEdited);
        }

        public RecordingDefaultState editVersion(DomainTypes.VersionCode value) {
            return new RecordingDefaultState(songId, key, value, keyEdited, true);
        }

        public RecordingDefaultState applySongDefaults(SongDefaults song) {
            return new RecordingDefaultState(song.songId, defaultKey(song), song.version, false, false);
        }

        private static DomainTypes.MusicalKey defaultKey(SongDefaults song) {
            return song.representativeKey == null ? DomainTypes.MusicalKey.original() : song.representativeKey;
        }
    }
}
