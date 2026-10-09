package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class CleanupCandidateTests {
 @Test void recomputesReasonsWithoutDeletingTheLastServerCopy(){var setup=new RetentionCandidatesTests();setup.setup();try{setup.selectionSchema();setup.db.execute("CREATE TABLE user_entitlement(user_id BINARY(16) PRIMARY KEY,quota_bytes BIGINT,pinned_limit INT,revision BIGINT)");setup.db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16),revision BIGINT,operation_id BINARY(16),requested_at TIMESTAMP)");CleanupCandidateDatabaseChecks.verify(setup.db);}finally{setup.close();}}
}
