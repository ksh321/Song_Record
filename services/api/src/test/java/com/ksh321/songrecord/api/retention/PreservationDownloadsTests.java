package com.ksh321.songrecord.api.retention;
import java.time.*;import java.util.*;import org.junit.jupiter.api.Test;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import com.ksh321.songrecord.api.auth.*;import com.ksh321.songrecord.api.storage.StorageObjectKeys;import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;import static org.assertj.core.api.Assertions.*;import static org.mockito.Mockito.*;
class PreservationDownloadsTests {
 @Test void onlyTheAuthenticatedStoredGenerationCanBeSigned(){
  var setup=new RetentionCandidatesTests();setup.setup();try{setup.selectionSchema();var db=setup.db;UUID owner=UUID.randomUUID(),id=UUID.randomUUID(),generation=UUID.randomUUID(),dev=UUID.randomUUID();var key=new StorageObjectKeys.Final(owner,id,generation);
   db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,sha256,verified_size,cloud_revision) VALUES(?,?,'STORED',?,?,?,12,3)",bytes(id),bytes(owner),key.value(),bytes(generation),"a".repeat(64));
   var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);var principal=new SessionService.Principal(owner,dev,UUID.randomUUID());when(account.principal()).thenReturn(principal);when(access.authenticate("fixture",dev.toString())).thenReturn(account);when(access.revalidate(account)).thenReturn(principal);
   var signer=mock(PreservationDownloadSigner.class);when(signer.sign(key)).thenReturn(new PreservationDownloadSigner.SignedGet("https://fixture.r2.cloudflarestorage.com/object",Instant.now().plusSeconds(300)));
   var service=new PreservationDownloads(db,access,new DataSourceTransactionManager(db.getDataSource()),signer);var ticket=service.ticket("fixture",dev.toString(),id);assertThat(ticket).containsEntry("user_id",owner.toString()).containsEntry("generation",generation.toString()).containsEntry("cloud_revision",3L);verify(signer).sign(key);
   assertThatThrownBy(()->service.ticket("fixture",dev.toString(),UUID.randomUUID())).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);db.update("UPDATE recording_asset SET cloud_state='DELETING' WHERE recording_id=?",bytes(id));assertThatThrownBy(()->service.ticket("fixture",dev.toString(),id)).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);verifyNoMoreInteractions(signer);
  }finally{setup.close();}
 }
}
