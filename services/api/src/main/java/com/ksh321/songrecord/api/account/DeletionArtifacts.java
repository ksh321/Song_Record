package com.ksh321.songrecord.api.account;
import java.time.Instant;
import java.util.UUID;

/** Trusted private maintenance boundary, not an upload or user-selected filesystem. */
public interface DeletionArtifacts {
 void record(UUID owner,long revision,Instant accepted)throws Exception;
 boolean recorded(UUID owner,long revision,Instant accepted)throws Exception;
 boolean purgeAndVerifyBackups(UUID owner)throws Exception;
 void retire(UUID owner)throws Exception;
}
