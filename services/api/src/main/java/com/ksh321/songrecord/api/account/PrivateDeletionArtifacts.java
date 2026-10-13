package com.ksh321.songrecord.api.account;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;
import tools.jackson.databind.json.JsonMapper;

/** Separate durable USER ledger plus reviewed private backup inventory; shared copies wait. */
public final class PrivateDeletionArtifacts implements DeletionArtifacts {
 private final Path ledger,backups;private final JsonMapper json=new JsonMapper();private final String environment;
 public PrivateDeletionArtifacts(Path ledger,Path backups)throws Exception{this(ledger,backups,"dev");}
 public PrivateDeletionArtifacts(Path ledger,Path backups,String environment)throws Exception{
  if(!Set.of("dev","prod").contains(environment))throw bad();this.environment=environment;
  this.ledger=root(ledger);this.backups=root(backups);
  if(this.ledger.startsWith(this.backups)||this.backups.startsWith(this.ledger))throw bad();
  catalog();
 }
 private void catalog()throws Exception{var path=backups.resolve(".catalog.json");if(!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)||Files.isSymbolicLink(path)||Files.size(path)>4096)throw bad();var row=json.readTree(Files.readAllBytes(path));if(row.path("schema").asInt()!=1||!"song-record-operational-backups-v1".equals(row.path("format").asText())||!environment.equals(row.path("environment").asText())||row.path("retention_days").asInt()!=7||!row.path("authoritative").asBoolean()||uuid(row.path("instance_id").asText())==null)throw bad();}
 private static Path root(Path p)throws Exception{var absolute=p.toAbsolutePath().normalize();if(!Files.isDirectory(absolute,LinkOption.NOFOLLOW_LINKS)||Files.isSymbolicLink(absolute)||!absolute.toRealPath().equals(absolute))throw bad();return absolute;}
 private static java.io.IOException bad(){return new java.io.IOException("DELETION_PRIVATE_ARCHIVE_UNAVAILABLE");}
 private Path entry(UUID owner)throws Exception{if(!root(ledger).equals(ledger))throw bad();var p=ledger.resolve(owner+".json");if(Files.isSymbolicLink(p)||Files.exists(p,LinkOption.NOFOLLOW_LINKS)&&!Files.isRegularFile(p,LinkOption.NOFOLLOW_LINKS))throw bad();return p;}
 private Map<String,Object> value(UUID owner,long revision,Instant accepted){return Map.of("schema",1,"entity_type","USER","owner_id",owner.toString(),"revision",revision,"accepted_at",accepted.toString());}
 public void record(UUID owner,long revision,Instant accepted)throws Exception{
  var p=entry(owner);if(Files.exists(p)){if(!recorded(owner,revision,accepted))throw bad();syncDirectory(ledger,p);return;}
  var bytes=json.writeValueAsBytes(value(owner,revision,accepted));var temporary=Files.createTempFile(ledger,"deletion-",".pending");
  try{try(var channel=FileChannel.open(temporary,StandardOpenOption.WRITE)){var buffer=java.nio.ByteBuffer.wrap(bytes);while(buffer.hasRemaining())channel.write(buffer);channel.force(true);}Files.move(temporary,p,StandardCopyOption.ATOMIC_MOVE);}
  finally{Files.deleteIfExists(temporary);}
  syncDirectory(ledger,p);if(!recorded(owner,revision,accepted))throw bad();
 }
 private void syncDirectory(Path directory,Path existing)throws Exception{try(var channel=FileChannel.open(directory,StandardOpenOption.READ)){channel.force(true);}catch(java.io.IOException unavailable){if(!environment.equals("dev")||!System.getProperty("os.name").startsWith("Windows"))throw bad();if(existing!=null&&Files.exists(existing))try(var channel=FileChannel.open(existing,StandardOpenOption.WRITE)){channel.force(true);}}}
 public boolean recorded(UUID owner,long revision,Instant accepted)throws Exception{var p=entry(owner);if(!Files.exists(p))return false;if(Files.size(p)>4096)throw bad();var tree=json.readTree(Files.readAllBytes(p));return tree.isObject()&&tree.size()==5&&tree.path("schema").isIntegralNumber()&&tree.path("schema").asInt()==1&&"USER".equals(tree.path("entity_type").asText())&&owner.toString().equals(tree.path("owner_id").asText())&&tree.path("revision").isIntegralNumber()&&tree.path("revision").asLong()==revision&&accepted.toString().equals(tree.path("accepted_at").asText());}
 public boolean purgeAndVerifyBackups(UUID owner)throws Exception{
  if(!root(backups).equals(backups))throw bad();catalog();boolean absent=true;
  try(var dirs=Files.newDirectoryStream(backups)){
   int count=0;
   for(var directory:dirs){if(directory.getFileName().toString().equals(".catalog.json"))continue;if(++count>10000)throw bad();var id=uuid(directory.getFileName().toString());if(id==null||!Files.isDirectory(directory,LinkOption.NOFOLLOW_LINKS)||Files.isSymbolicLink(directory)||!directory.toRealPath().equals(directory))throw bad();
    var manifest=directory.resolve("manifest.json");var payload=directory.resolve("payload.zip");
    try(var files=Files.newDirectoryStream(directory)){for(var f:files)if(!Set.of(manifest,payload).contains(f))throw bad();}
    if(!Files.isRegularFile(manifest,LinkOption.NOFOLLOW_LINKS)||Files.exists(payload,LinkOption.NOFOLLOW_LINKS)&&!Files.isRegularFile(payload,LinkOption.NOFOLLOW_LINKS)||Files.isSymbolicLink(manifest)||Files.isSymbolicLink(payload)||Files.size(manifest)>65536)throw bad();
    var tree=json.readTree(Files.readAllBytes(manifest));if(tree.path("schema").asInt()!=1||!id.toString().equals(tree.path("artifact_id").asText())||!tree.path("subjects").isArray()||tree.path("subjects").isEmpty()||!tree.path("sha256").asText().matches("[0-9a-f]{64}"))throw bad();
    var subjects=new HashSet<UUID>();for(var subject:tree.path("subjects")){var user=uuid(subject.asText());if(user==null||!subjects.add(user))throw bad();}
    Instant.parse(tree.path("created_at").asText());
    if(!subjects.contains(owner))continue;
    if(subjects.size()!=1){absent=false;continue;} // Never erase another owner's shared recovery copy.
    if(!Files.exists(payload,LinkOption.NOFOLLOW_LINKS)){Files.delete(manifest);Files.delete(directory);syncDirectory(backups,null);continue;}
    var digest=MessageDigest.getInstance("SHA-256");try(var input=Files.newInputStream(payload)){var buffer=new byte[32768];for(int n;(n=input.read(buffer))>=0;)if(n>0)digest.update(buffer,0,n);}
    if(!HexFormat.of().formatHex(digest.digest()).equals(tree.path("sha256").asText()))throw bad();
    if(!root(backups).equals(backups)||!directory.toRealPath().equals(directory)||Files.isSymbolicLink(payload))throw bad();
    Files.delete(payload);Files.delete(manifest);Files.delete(directory);syncDirectory(backups,null);
   }
  }
  return absent;
 }
 public void retire(UUID owner)throws Exception{if(!purgeAndVerifyBackups(owner))throw bad();Files.deleteIfExists(entry(owner));syncDirectory(ledger,null);}
 public void requireRestorable(Set<UUID> subjects)throws Exception{for(var owner:subjects)if(blocksRestore(owner))throw new java.io.IOException("DELETED_OWNER_RESTORE_FORBIDDEN");}
 public boolean blocksRestore(UUID owner)throws Exception{var p=entry(owner);if(!Files.exists(p))return false;if(Files.size(p)>4096)throw bad();var row=json.readTree(Files.readAllBytes(p));if(!"USER".equals(row.path("entity_type").asText())||!owner.toString().equals(row.path("owner_id").asText()))throw bad();return true;}
 private static UUID uuid(String value){try{var id=UUID.fromString(value);return id.toString().equals(value)&&!id.equals(new UUID(0,0))?id:null;}catch(IllegalArgumentException e){return null;}}
}
