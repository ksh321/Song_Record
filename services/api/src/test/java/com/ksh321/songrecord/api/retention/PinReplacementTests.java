package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;import org.springframework.jdbc.core.JdbcTemplate;
class PinReplacementTests {
 static JdbcTemplate database(){var db=UploadApprovalTests.database();db.execute("ALTER TABLE user_entitlement ADD pinned_limit INT DEFAULT 10");db.execute("ALTER TABLE user_entitlement ADD revision BIGINT DEFAULT 1");db.execute("ALTER TABLE pin_slot ADD revision BIGINT DEFAULT 1");db.execute("ALTER TABLE pin_slot ADD updated_at TIMESTAMP");db.execute("CREATE UNIQUE INDEX uq_pin_replace_asset_key ON recording_asset(object_key)");return db;}
 @Test void tenSlotsKeepCurrentAndReplacementCannotBypassQuota()throws Exception{PinReplacementDatabaseChecks.verify(database());}
}
