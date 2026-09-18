package com.ksh321.songrecord.api.domain;

import java.nio.ByteBuffer;
import java.util.Objects;
import java.util.UUID;

public final class DomainTypes {
    private DomainTypes() {}

    public record SongId(UUID value) implements Comparable<SongId> {
        public SongId { Objects.requireNonNull(value, "value"); }
        public static SongId parse(String value) { return new SongId(UUID.fromString(value)); }
        public static SongId fromBytes(byte[] bytes) { return new SongId(uuidFromBytes(bytes)); }
        public byte[] bytes() { return uuidBytes(value); }
        @Override public int compareTo(SongId other) { return compareUuid(value, other.value); }
        @Override public String toString() { return value.toString(); }
    }

    public record RecordingId(UUID value) implements Comparable<RecordingId> {
        public RecordingId { Objects.requireNonNull(value, "value"); }
        public static RecordingId parse(String value) { return new RecordingId(UUID.fromString(value)); }
        public static RecordingId fromBytes(byte[] bytes) { return new RecordingId(uuidFromBytes(bytes)); }
        public byte[] bytes() { return uuidBytes(value); }
        @Override public int compareTo(RecordingId other) { return compareUuid(value, other.value); }
        @Override public String toString() { return value.toString(); }
    }

    public record TjNumber(String value) {
        public TjNumber {
            value = InputContracts.trimContractWhitespace(value);
            if (value.isEmpty() || value.length() > 20 || !value.matches("[0-9]+")) {
                throw new IllegalArgumentException("TJ 번호는 1~20자리 숫자여야 합니다.");
            }
        }
    }

    public enum VersionCode { NORMAL, MR, LIVE }
    public enum KeyMode { ORIGINAL, MALE, FEMALE }
    public enum SongTier { S, A, B, C, D }
    public enum RecordingTier { S, A, B, C, D }

    public record MusicalKey(KeyMode mode, int shift) {
        public MusicalKey {
            Objects.requireNonNull(mode, "mode");
            if (shift < -12 || shift > 12) {
                throw new IllegalArgumentException("키 이동은 -12~+12 범위여야 합니다.");
            }
            if (mode == KeyMode.ORIGINAL && shift != 0) {
                throw new IllegalArgumentException("원키의 이동값은 0이어야 합니다.");
            }
        }

        public static MusicalKey original() { return new MusicalKey(KeyMode.ORIGINAL, 0); }
    }

    public static String formatVersion(VersionCode version) {
        return switch (version) {
            case NORMAL -> "일반 반주";
            case MR -> "MR";
            case LIVE -> "LIVE";
        };
    }

    public static String formatKey(MusicalKey key) {
        if (key == null) return "미정";
        if (key.mode == KeyMode.ORIGINAL) return "원키";
        var prefix = key.mode == KeyMode.MALE ? "남" : "여";
        var shift = key.shift > 0 ? "+" + key.shift : Integer.toString(key.shift);
        return prefix + " " + shift;
    }

    public static String formatTier(Enum<?> tier) {
        return tier == null ? "미정" : tier.name();
    }

    public enum LocalState { CAPTURING, INPUT_PENDING, SAVED, INTERRUPTED, CORRUPT }
    public enum MetadataState { DRAFT, SAVED }
    public enum SyncState { PENDING, SYNCING, SYNCED, CONFLICT }
    public enum CloudState { NONE, QUEUED, UPLOADING, VERIFYING, STORED, DELETING }
    public enum BlockedReason { FILE_MISSING, QUOTA, PIN_LIMIT, BUDGET, AUTH, NETWORK, FILE_INVALID }
    public enum LifecycleState { ACTIVE, TRASHED, PURGE_PENDING, PURGED }

    private static byte[] uuidBytes(UUID value) {
        return ByteBuffer.allocate(16)
                .putLong(value.getMostSignificantBits())
                .putLong(value.getLeastSignificantBits())
                .array();
    }

    private static UUID uuidFromBytes(byte[] bytes) {
        if (bytes == null || bytes.length != 16) {
            throw new IllegalArgumentException("UUID는 16바이트여야 합니다.");
        }
        var buffer = ByteBuffer.wrap(bytes);
        return new UUID(buffer.getLong(), buffer.getLong());
    }

    private static int compareUuid(UUID left, UUID right) {
        var most = Long.compareUnsigned(left.getMostSignificantBits(), right.getMostSignificantBits());
        return most != 0 ? most : Long.compareUnsigned(left.getLeastSignificantBits(), right.getLeastSignificantBits());
    }
}
