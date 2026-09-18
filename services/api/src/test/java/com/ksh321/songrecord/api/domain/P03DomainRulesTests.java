package com.ksh321.songrecord.api.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import org.json.JSONObject;
import org.junit.jupiter.api.Test;

class P03DomainRulesTests {
    @Test
    void relinkingPreservesTheRecordedSnapshot() {
        var firstSong = DomainTypes.SongId.parse("00000000-0000-4000-8000-000000000010");
        var nextSong = DomainTypes.SongId.parse("00000000-0000-4000-8000-000000000011");
        var snapshot = new RecordingModels.RecordingSnapshot(
                DomainTypes.RecordingId.parse("00000000-0000-4000-8000-000000000001"),
                firstSong,
                "당시 곡명",
                "당시 가수",
                new DomainTypes.MusicalKey(DomainTypes.KeyMode.FEMALE, 1),
                DomainTypes.VersionCode.LIVE,
                "당시 메모",
                Instant.parse("2026-09-17T16:00:00Z"),
                "Asia/Seoul",
                540);

        var relinked = snapshot.relink(nextSong);
        assertThat(relinked.songId()).isEqualTo(nextSong);
        assertThat(relinked.title()).isEqualTo(snapshot.title());
        assertThat(relinked.artist()).isEqualTo(snapshot.artist());
        assertThat(relinked.key()).isEqualTo(snapshot.key());
        assertThat(relinked.version()).isEqualTo(snapshot.version());
        assertThat(relinked.note()).isEqualTo(snapshot.note());
        assertThat(relinked.recordedAt()).isEqualTo(snapshot.recordedAt());
    }

    @Test
    void songSelectionChangesOnlyDefaultsTheUserDidNotEdit() {
        var first = new RecordingModels.SongDefaults(
                DomainTypes.SongId.parse("00000000-0000-4000-8000-000000000010"),
                DomainTypes.VersionCode.MR,
                new DomainTypes.MusicalKey(DomainTypes.KeyMode.MALE, -1));
        var next = new RecordingModels.SongDefaults(
                DomainTypes.SongId.parse("00000000-0000-4000-8000-000000000011"),
                DomainTypes.VersionCode.LIVE,
                new DomainTypes.MusicalKey(DomainTypes.KeyMode.FEMALE, 2));

        var state = RecordingModels.RecordingDefaultState.initial().selectSong(first)
                .editKey(new DomainTypes.MusicalKey(DomainTypes.KeyMode.MALE, 3));
        var selected = state.selectSong(next);
        assertThat(selected.key()).isEqualTo(new DomainTypes.MusicalKey(DomainTypes.KeyMode.MALE, 3));
        assertThat(selected.version()).isEqualTo(DomainTypes.VersionCode.LIVE);
        assertThat(selected.keyEdited()).isTrue();
        assertThat(selected.versionEdited()).isFalse();

        var reset = selected.applySongDefaults(next);
        assertThat(reset.key()).isEqualTo(next.representativeKey());
        assertThat(reset.version()).isEqualTo(next.version());
        assertThat(reset.keyEdited()).isFalse();
        assertThat(reset.versionEdited()).isFalse();
    }

    @Test
    void sortingFixtureMatchesSrSortOne() throws Exception {
        var root = fixture("contracts/sorting.json");
        var cases = root.getJSONArray("cases");
        for (var caseIndex = 0; caseIndex < cases.length(); caseIndex++) {
            var testCase = cases.getJSONObject(caseIndex);
            var rowsJson = testCase.getJSONObject("input").getJSONArray("rows");
            var rows = new ArrayList<DomainOrdering.TitleRow>();
            for (var index = 0; index < rowsJson.length(); index++) {
                var row = rowsJson.getJSONObject(index);
                rows.add(new DomainOrdering.TitleRow(
                        DomainTypes.SongId.parse(row.getString("id")), row.getString("title")));
            }
            var actual = DomainOrdering.sortByTitle(rows).stream()
                    .map(row -> row.id().toString()).toList();
            var expectedJson = testCase.getJSONObject("expected").getJSONArray("ids");
            var expected = new ArrayList<String>();
            for (var index = 0; index < expectedJson.length(); index++) expected.add(expectedJson.getString(index));
            assertThat(actual).as(testCase.getString("id")).containsExactlyElementsOf(expected);
        }
        assertThat(DomainOrdering.compareSortText("가", "가")).isZero();
    }

    @Test
    void recordingSelectionFixtureReturnsTheSameRoles() throws Exception {
        var root = fixture("retention/selection.json");
        var cases = root.getJSONArray("cases");
        for (var caseIndex = 0; caseIndex < cases.length(); caseIndex++) {
            var testCase = cases.getJSONObject(caseIndex);
            var input = testCase.getJSONObject("input");
            var candidatesJson = input.getJSONArray("recordings");
            var candidates = new ArrayList<DomainOrdering.RecordingCandidate>();
            for (var index = 0; index < candidatesJson.length(); index++) {
                var candidate = candidatesJson.getJSONObject(index);
                candidates.add(new DomainOrdering.RecordingCandidate(
                        DomainTypes.RecordingId.parse(candidate.getString("id")),
                        Instant.parse(candidate.getString("recorded_at")),
                        candidate.isNull("tier") ? null : DomainTypes.RecordingTier.valueOf(candidate.getString("tier")),
                        candidate.getString("lifecycle").equals("ACTIVE")
                                && candidate.getString("metadata").equals("SAVED")
                                && candidate.getBoolean("valid_file_manifest")));
            }
            var representative = input.isNull("representative_id") ? null
                    : DomainTypes.RecordingId.parse(input.getString("representative_id"));
            var result = DomainOrdering.selectRecordingRoles(candidates, representative);
            var expected = testCase.getJSONObject("expected");
            assertThat(value(result.representative())).as(testCase.getString("id") + " representative")
                    .isEqualTo(nullableString(expected, "representative"));
            assertThat(value(result.latest())).as(testCase.getString("id") + " latest")
                    .isEqualTo(nullableString(expected, "latest"));
            assertThat(value(result.lowestTier())).as(testCase.getString("id") + " lowest")
                    .isEqualTo(nullableString(expected, "lowest"));
            var idsJson = expected.getJSONArray("unique_ids");
            var expectedIds = new HashSet<String>();
            for (var index = 0; index < idsJson.length(); index++) expectedIds.add(idsJson.getString(index));
            assertThat(result.uniqueIds().stream().map(Object::toString).toList())
                    .containsExactlyInAnyOrderElementsOf(expectedIds);
        }
    }

    private static JSONObject fixture(String path) throws Exception {
        var json = Files.readString(Path.of("../../fixtures/" + path), StandardCharsets.UTF_8);
        return new JSONObject(json);
    }

    private static String value(Object value) {
        return value == null ? null : value.toString();
    }

    private static String nullableString(JSONObject object, String key) throws Exception {
        return object.isNull(key) ? null : object.getString(key);
    }
}
