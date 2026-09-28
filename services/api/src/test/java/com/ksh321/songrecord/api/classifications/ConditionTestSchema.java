package com.ksh321.songrecord.api.classifications;

import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.domain.DomainOrdering;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** H2 projection: VARCHAR uses UTF-16 units, while the real MySQL limit is 50 code points. */
public final class ConditionTestSchema {
    private ConditionTestSchema(){}
    public static void install(JdbcTemplate db){
        db.execute("ALTER TABLE recording ALTER COLUMN condition_code VARCHAR(36)");
        db.execute("ALTER TABLE recording ALTER COLUMN condition_name_snapshot VARCHAR(100)");
        db.execute("CREATE TABLE condition_definition(id BINARY(16) PRIMARY KEY,user_id BINARY(16),code VARCHAR(36),name VARCHAR(100),normalized_name_key VARBINARY(800),archived_at TIMESTAMP(3),revision BIGINT DEFAULT 1,created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,updated_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,active_name_key VARBINARY(800) GENERATED ALWAYS AS (CASE WHEN archived_at IS NULL THEN normalized_name_key ELSE NULL END),UNIQUE(user_id,code),UNIQUE(user_id,active_name_key))");
        for(byte[] owner:db.queryForList("SELECT id FROM app_user",byte[].class))for(var c:db.queryForList("SELECT code,name FROM condition_catalog")){
            String code=(String)c.get("code"),name=(String)c.get("name");UUID id=UUID.nameUUIDFromBytes((java.util.HexFormat.of().formatHex(owner)+code).getBytes(StandardCharsets.UTF_8));
            db.update("INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key) VALUES(?,?,?,?,?)",bytes(id),owner,code,name,DomainOrdering.normalizeText(name).getBytes(StandardCharsets.UTF_8));
        }
    }
}
