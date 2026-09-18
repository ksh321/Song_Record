package com.ksh321.songrecord.api.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

class DomainContractsTests {
    @Test
    void identifiersKeepTheirMeaningAndOrdering() {
        var song = DomainTypes.SongId.parse("00000000-0000-4000-8000-0000000000AA");
        var recording = DomainTypes.RecordingId.parse("00000000-0000-4000-8000-0000000000ab");

        assertThat(song.toString()).endsWith("00aa");
        assertThat(song.bytes()).hasSize(16);
        assertThat(DomainTypes.SongId.fromBytes(song.bytes())).isEqualTo(song);
        assertThat(song.compareTo(DomainTypes.SongId.parse(recording.toString()))).isNegative();
        assertThat(new DomainTypes.TjNumber(" 00123 ").value()).isEqualTo("00123");
        assertThat(new DomainTypes.TjNumber("00123")).isNotEqualTo(new DomainTypes.TjNumber("123"));
    }

    @Test
    void keyVersionAndTierDisplaysFollowTheContract() {
        assertThat(DomainTypes.formatVersion(DomainTypes.VersionCode.NORMAL)).isEqualTo("일반 반주");
        assertThat(DomainTypes.formatKey(DomainTypes.MusicalKey.original())).isEqualTo("원키");
        assertThat(DomainTypes.formatKey(new DomainTypes.MusicalKey(DomainTypes.KeyMode.MALE, 0))).isEqualTo("남 0");
        assertThat(DomainTypes.formatKey(new DomainTypes.MusicalKey(DomainTypes.KeyMode.FEMALE, 1))).isEqualTo("여 +1");
        assertThat(DomainTypes.formatTier(null)).isEqualTo("미정");
        assertThatThrownBy(() -> new DomainTypes.MusicalKey(DomainTypes.KeyMode.ORIGINAL, 13))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void inputFixtureCasesUseUnicodeCodePointsAndNormalizedNewlines() throws Exception {
        var json = Files.readString(Path.of("../../fixtures/contracts/input.json"), StandardCharsets.UTF_8);
        var casePattern = Pattern.compile(
                "\\\"id\\\"\\s*:\\s*\\\"([^\\\"]+)\\\".*?\\\"field\\\"\\s*:\\s*\\\"([^\\\"]+)\\\".*?"
                        + "\\\"value\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"])*)\\\".*?\\\"expected\\\"\\s*:\\s*\\{.*?"
                        + "\\\"actual\\\"\\s*:\\s*(\\d+).*?\\\"valid\\\"\\s*:\\s*(true|false)",
                Pattern.DOTALL);
        var matcher = casePattern.matcher(json);
        var count = 0;
        while (matcher.find()) {
            var field = InputContracts.Field.valueOf(matcher.group(2).toUpperCase());
            var value = unescapeJsonString(matcher.group(3));
            var result = InputContracts.validate(field, value);
            assertThat(result.actual()).as(matcher.group(1)).isEqualTo(Integer.parseInt(matcher.group(4)));
            assertThat(result.valid()).as(matcher.group(1)).isEqualTo(Boolean.parseBoolean(matcher.group(5)));
            count++;
        }
        assertThat(count).isEqualTo(11);
        assertThat(InputContracts.validate(InputContracts.Field.NOTE, "a\r\nb\rc").normalized())
                .isEqualTo("a\nb\nc");
    }

    private static String unescapeJsonString(String value) {
        return value.replace("\\r", "\r")
                .replace("\\n", "\n")
                .replace("\\t", "\t")
                .replace("\\\"", "\"")
                .replace("\\\\", "\\");
    }
}
