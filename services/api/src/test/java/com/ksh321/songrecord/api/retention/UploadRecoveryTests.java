package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadRecoveryTests {
 @Test void terminalTransitionsAreIdempotentAndLeaseFenced()throws Exception{var db=UploadFinalizationTests.database();try(var c=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(c);UploadRecoveryDatabaseChecks.verify(db);}}
 @Test void alreadyWrittenFinalBytesRecoverWithoutTemporaryDownload()throws Exception{
  var db=UploadFinalizationTests.database();try(var c=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(c);var f=UploadFinalizationDatabaseChecks.fixture(db);
   var audio=org.mockito.Mockito.mock(com.ksh321.songrecord.api.uploads.AudioValidator.Validated.class);org.mockito.Mockito.when(audio.bytes()).thenAnswer(call->java.nio.ByteBuffer.wrap(new byte[]{1,2,3}).asReadOnlyBuffer());org.mockito.Mockito.when(audio.sha256()).thenReturn("a".repeat(64));
   var validator=org.mockito.Mockito.mock(com.ksh321.songrecord.api.uploads.AudioValidator.class);org.mockito.Mockito.when(validator.validate(org.mockito.ArgumentMatchers.any(),org.mockito.ArgumentMatchers.eq(3L),org.mockito.ArgumentMatchers.eq("a".repeat(64)))).thenReturn(audio);
   var writes=new java.util.concurrent.atomic.AtomicInteger();var objects=new com.ksh321.songrecord.api.uploads.UploadFinalObjects(){public void ensure(com.ksh321.songrecord.api.storage.StorageObjectKeys.Final k,java.nio.ByteBuffer b,String h){writes.incrementAndGet();}public java.util.Optional<java.nio.ByteBuffer> read(com.ksh321.songrecord.api.storage.StorageObjectKeys.Final k){return java.util.Optional.of(java.nio.ByteBuffer.wrap(new byte[]{1,2,3}));}};
   f.clock().now=f.clock().now.plusSeconds(121);var reclaimed=f.jobs().claim(com.ksh321.songrecord.api.jobs.JobQueue.Type.UPLOAD_VERIFY).orElseThrow();org.assertj.core.api.Assertions.assertThat(f.jobs().complete(f.lease(),()->{throw new AssertionError("stale worker effects");})).isFalse();var effects=new com.ksh321.songrecord.api.uploads.UploadFinalization(db,objects,f.clock()).recover(reclaimed,validator).orElseThrow();org.assertj.core.api.Assertions.assertThat(f.jobs().complete(reclaimed,effects)).isTrue();org.assertj.core.api.Assertions.assertThat(writes).hasValue(1);
  }
 }
}
