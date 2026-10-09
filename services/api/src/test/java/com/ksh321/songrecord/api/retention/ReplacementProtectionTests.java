package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class ReplacementProtectionTests {
 @Test void previousGenerationSurvivesWaitingSupersededAndWithdrawnRoles(){var f=new RetentionCandidatesTests();f.setup();try{f.selectionSchema();ReplacementProtectionDatabaseChecks.verify(f.db);}finally{f.close();}}
}
