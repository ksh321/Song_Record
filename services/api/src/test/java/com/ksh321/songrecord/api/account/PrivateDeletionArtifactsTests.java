package com.ksh321.songrecord.api.account;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;
class PrivateDeletionArtifactsTests {
 @TempDir Path root;
 static void catalog(Path backups)throws Exception{Files.writeString(backups.resolve(".catalog.json"),new tools.jackson.databind.json.JsonMapper().writeValueAsString(Map.of("schema",1,"format","song-record-operational-backups-v1","environment","dev","retention_days",7,"authoritative",true,"instance_id",UUID.randomUUID().toString())));}
 @Test void archivedOwnerCannotRestoreEvenAfterDatabaseRemovalAndInterruptedPayloadRemovalIsIdempotent()throws Exception{
  var ledger=Files.createDirectory(root.resolve("ledger"));var backups=Files.createDirectory(root.resolve("backups"));catalog(backups);var owner=UUID.randomUUID();var other=UUID.randomUUID();var at=Instant.parse("2026-10-13T00:00:00Z");
  var archive=new PrivateDeletionArtifacts(ledger,backups);archive.record(owner,2,at);archive.record(owner,2,at);
  var restarted=new PrivateDeletionArtifacts(ledger,backups);assertThat(restarted.recorded(owner,2,at)).isTrue();assertThatThrownBy(()->restarted.requireRestorable(Set.of(owner))).isInstanceOf(java.io.IOException.class);restarted.requireRestorable(Set.of(other));
  var id=UUID.randomUUID();var dir=Files.createDirectory(backups.resolve(id.toString()));Files.writeString(dir.resolve("manifest.json"),new tools.jackson.databind.json.JsonMapper().writeValueAsString(Map.of("schema",1,"artifact_id",id.toString(),"subjects",List.of(owner.toString()),"created_at",at.toString(),"sha256","a".repeat(64))));
  assertThat(restarted.purgeAndVerifyBackups(owner)).isTrue();assertThat(Files.exists(dir)).isFalse();restarted.retire(owner);assertThat(restarted.blocksRestore(owner)).isFalse();
 }
 @Test void wrongEnvironmentUnknownInventoryAndChecksumFailureCannotAuthorizeBackupCompletion()throws Exception{
  var ledger=Files.createDirectory(root.resolve("ledger"));var backups=Files.createDirectory(root.resolve("backups"));catalog(backups);
  assertThatThrownBy(()->new PrivateDeletionArtifacts(ledger,backups,"prod")).isInstanceOf(java.io.IOException.class);
  var archive=new PrivateDeletionArtifacts(ledger,backups);Files.writeString(backups.resolve("unknown.dump"),"synthetic");assertThatThrownBy(()->archive.purgeAndVerifyBackups(UUID.randomUUID())).isInstanceOf(java.io.IOException.class);assertThat(Files.exists(backups.resolve("unknown.dump"))).isTrue();
 }
}
