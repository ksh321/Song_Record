package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.uploads.*;import com.ksh321.songrecord.api.storage.*;
import java.time.*;import java.util.*;import java.nio.*;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;import static org.mockito.Mockito.*;
/** Failure after capture/write must preserve the prior server generation and release only the new reservation. */
public final class UploadFailureDatabaseChecks {
 public static void verify(JdbcTemplate db)throws Exception{
  for(String scenario:List.of("withdrawn","song-deleted","file-missing","cancelled","invalid","policy-changed","prior-same-recording")){
   var f=UploadFinalizationDatabaseChecks.fixture(db);var manager=new DataSourceTransactionManager(db.getDataSource());var recovery=new UploadRecovery(db,manager,f.clock());
   UUID old=scenario.equals("prior-same-recording")?f.recording():recording(db,f.owner(),device(db,f.owner()),null,false,false,"VALIDATED");String hash="a".repeat(64);var oldKey=new StorageObjectKeys.Final(f.owner(),old,UUID.randomUUID());
   if(!scenario.equals("prior-same-recording"))db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,3,1000,'AAC_LC',48000,1,'VALIDATED')",bytes(old),bytes(f.owner()),hash);
   db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(old));
   db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at,cloud_revision) VALUES(?,?,'STORED',?,?,3,?,CURRENT_TIMESTAMP,2)",bytes(old),bytes(f.owner()),oldKey.value(),bytes(oldKey.generation()),hash);
   db.update("UPDATE storage_usage SET used_bytes=used_bytes+3 WHERE user_id=?",bytes(f.owner()));db.update("UPDATE global_storage_usage SET used_bytes=used_bytes+3 WHERE id=1");
   var before=db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?",bytes(old));long globalUsed=db.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class);byte[] original={7,8,9};var contents=new HashMap<String,byte[]>();contents.put(oldKey.value(),original.clone());
   var audio=mock(AudioValidator.Validated.class);when(audio.bytes()).thenAnswer(c->ByteBuffer.wrap(new byte[]{1,2,3}));when(audio.sha256()).thenReturn(hash);
   var fin=new UploadFinalization(db,(key,buffer,h)->{byte[] b=new byte[buffer.remaining()];buffer.get(b);contents.put(key.value(),b);},f.clock());
   if(scenario.equals("file-missing")){
    var read=new UploadVerification(db,key->{throw new IllegalStateException("UPLOAD_BYTES_UNAVAILABLE");},f.clock());assertThatThrownBy(()->read.prepare(f.lease(),(lease,data)->{throw new AssertionError("Missing bytes reached validation");})).isInstanceOf(IllegalStateException.class).hasMessage("UPLOAD_BYTES_UNAVAILABLE");
   }else if(scenario.equals("invalid")){
    var read=new UploadVerification(db,key->new java.io.ByteArrayInputStream(new byte[]{1,2,3}),f.clock());assertThatThrownBy(()->read.prepare(f.lease(),(lease,data)->{new AudioValidator("ffmpeg","ffprobe").validate(data.bytes(),data.expectedSize(),data.expectedSha256());throw new AssertionError("Invalid checksum accepted");})).isInstanceOf(AudioValidator.Invalid.class);
   }else{
    if(scenario.equals("song-deleted")){UUID song=song(db,f.owner());db.update("UPDATE recording SET song_id=? WHERE id=?",bytes(song),bytes(f.recording()));}
    Runnable effects=fin.prepare(f.lease(),audio);
    switch(scenario){
     case "withdrawn"->db.update("DELETE FROM pin_slot WHERE user_id=?",bytes(f.owner()));
     case "song-deleted"->db.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=(SELECT song_id FROM recording WHERE id=?)",bytes(f.recording()));
     case "cancelled"->recovery.cancel(f.owner(),f.attempt());
     case "policy-changed"->db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,cloud_revision) VALUES(?,?,'NONE',2)",bytes(f.recording()),bytes(f.owner()));
     case "prior-same-recording"->{ } // A concurrently installed generation must never be replaced.
     default->throw new AssertionError();
    }
    if(scenario.equals("cancelled"))assertThat(f.jobs().complete(f.lease(),effects)).isFalse();else assertThatThrownBy(()->f.jobs().complete(f.lease(),effects)).isInstanceOf(IllegalStateException.class);
   }
   if(!scenario.equals("cancelled"))assertThat(recovery.failed(f.lease(),"FILE_INVALID")).isEqualTo("FAILED");
   recovery.failed(f.lease(),"FILE_INVALID");recovery.cancel(f.owner(),f.attempt());
   assertThat(db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?",bytes(old))).usingRecursiveComparison().isEqualTo(before);
   assertThat(db.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isEqualTo(3);
   assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();assertThat(db.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(globalUsed);
   f.clock().now=f.clock().now.plusSeconds(121);var storage=mock(R2Storage.class);doAnswer(c->{contents.remove(((StorageObjectKeys.Final)c.getArgument(0)).value());return null;}).when(storage).deleteUncommittedFinal(any());recovery.cleanup(storage);
   assertThat(contents.get(oldKey.value())).containsExactly(original);org.mockito.Mockito.verify(storage,never()).deleteUncommittedFinal(oldKey);
   assertThat(db.queryForObject("SELECT COUNT(*) FROM change_log WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();
  }
 }
}
