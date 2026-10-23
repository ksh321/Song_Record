package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.web.ApiException;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Resolve under the caller's USER_SYNC transaction; never trust a client name. */
public final class ConditionSelection {
    private ConditionSelection() {}
    public static String name(JdbcTemplate jdbc, UUID owner, String code) {
        if (code == null) return null;
        var rows = jdbc.queryForList("SELECT name,archived_at FROM condition_definition WHERE user_id=? AND code=?", bytes(owner), code);
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","컨디션을 찾을 수 없습니다.",false,Map.of());
        var row = rows.getFirst();
        if (row.get("archived_at") != null) throw new ApiException(HttpStatus.CONFLICT,"CONDITION_ARCHIVED","선택 목록에서 삭제된 컨디션입니다.",false,Map.of());
        return (String) row.get("name");
    }
}
