package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class PinCompletionTests {
 @Test void atomicPromotionCancellationStaleFailureAndRollback()throws Exception{var db=UploadFinalizationTests.database();db.execute("ALTER TABLE user_entitlement ADD pinned_limit INT DEFAULT 10");db.execute("ALTER TABLE user_entitlement ADD revision BIGINT DEFAULT 1");db.execute("ALTER TABLE cloud_hold ADD id BINARY(16)");db.execute("ALTER TABLE cloud_hold ADD reason VARCHAR(32)");db.execute("ALTER TABLE cloud_hold ADD related_operation_id BINARY(16)");db.execute("ALTER TABLE cloud_hold ADD required_selection_revision BIGINT");db.execute("CREATE UNIQUE INDEX uq_pin_complete_asset_key ON recording_asset(object_key)");try(var keeper=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(keeper);PinCompletionDatabaseChecks.verify(db);}}
}
