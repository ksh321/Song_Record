package com.ksh321.songrecord.api.operations;
import com.ksh321.songrecord.api.account.DeletionArtifacts;
import java.time.Instant;
import java.util.UUID;
/** Live remote backup mirror owns absence confirmation. No assumed empty local catalog. */
public final class BackupDeletionArtifacts implements DeletionArtifacts {
 private final BackupDeletionFence fence;
 public BackupDeletionArtifacts(BackupDeletionFence fence){this.fence=fence;}
 public void record(UUID owner,long revision,Instant accepted){if(revision<1||accepted==null)throw new IllegalArgumentException();fence.user(owner,accepted);}
 public boolean recorded(UUID owner,long revision,Instant accepted){record(owner,revision,accepted);return true;}
 public boolean purgeAndVerifyBackups(UUID owner){return fence.ownerBackupsAbsent(owner);}
 public void retire(UUID owner){if(!fence.ownerBackupsAbsent(owner))throw new BackupDeletionFence.Awaiting();}
}
