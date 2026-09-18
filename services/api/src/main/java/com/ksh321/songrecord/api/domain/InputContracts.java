package com.ksh321.songrecord.api.domain;

import java.util.Objects;

public final class InputContracts {
    private InputContracts() {}

    public enum Field { TITLE, ARTIST, NOTE, TAG, CONDITION, PLAYLIST }

    public record Result(String normalized, int actual, int min, int max, boolean valid) {}

    public static Result validate(Field field, String raw) {
        Objects.requireNonNull(field, "field");
        Objects.requireNonNull(raw, "raw");

        var normalized = field == Field.NOTE
                ? raw.replace("\r\n", "\n").replace('\r', '\n')
                : trimContractWhitespace(raw);
        var min = field == Field.NOTE ? 0 : 1;
        var max = switch (field) {
            case TITLE, ARTIST -> 200;
            case NOTE -> 2_000;
            case TAG, CONDITION -> 50;
            case PLAYLIST -> 100;
        };
        var actual = normalized.codePointCount(0, normalized.length());
        return new Result(normalized, actual, min, max, actual >= min && actual <= max);
    }

    public static String trimContractWhitespace(String value) {
        Objects.requireNonNull(value, "value");
        var start = 0;
        var end = value.length();
        while (start < end) {
            var codePoint = value.codePointAt(start);
            if (!isContractWhitespace(codePoint)) break;
            start += Character.charCount(codePoint);
        }
        while (end > start) {
            var codePoint = value.codePointBefore(end);
            if (!isContractWhitespace(codePoint)) break;
            end -= Character.charCount(codePoint);
        }
        return value.substring(start, end);
    }

    private static boolean isContractWhitespace(int codePoint) {
        return (codePoint >= 0x0009 && codePoint <= 0x000d)
                || codePoint == 0x0020
                || codePoint == 0x0085
                || codePoint == 0x00a0
                || codePoint == 0x1680
                || (codePoint >= 0x2000 && codePoint <= 0x200a)
                || codePoint == 0x2028
                || codePoint == 0x2029
                || codePoint == 0x202f
                || codePoint == 0x205f
                || codePoint == 0x3000;
    }
}
