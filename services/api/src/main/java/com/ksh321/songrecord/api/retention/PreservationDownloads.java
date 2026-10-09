package com.ksh321.songrecord.api.retention;
import java.util.*;import org.springframework.context.annotation.Profile;import org.springframework.stereotype.Component;import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.transaction.support.TransactionTemplate;import org.springframework.http.HttpStatus;
import com.ksh321.songrecord.api.auth.AccountAccess;import com.ksh321.songrecord.api.web.ApiException;import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
@Component @Profile("!bootstrap") @ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
public final class PreservationDownloads {
 private final JdbcTemplate db;private final AccountAccess access;private final PreservationDownloadSigner signer;private final TransactionTemplate read;
 public PreservationDownloads(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,PreservationDownloadSigner signer){this.db=db;this.access=access;this.signer=signer;read=new TransactionTemplate(manager);read.setReadOnly(true);}
 public Map<String,Object> ticket(String auth,String device,UUID recording){
  var account=access.authenticate(auth,device);UUID owner=account.principal().userId();
  var asset=read.execute(s->{access.revalidate(account);var rows=db.queryForList("SELECT generation,object_key,sha256,verified_size,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='STORED'",bytes(owner),bytes(recording));if(rows.isEmpty())throw new ApiException(HttpStatus.CONFLICT,"FILE_NOT_STORED","서버 파일 보관 상태를 다시 확인해 주세요.",false,Map.of());return rows.getFirst();});
  UUID generation=uuid((byte[])asset.get("generation"));var key=new StorageObjectKeys.Final(owner,recording,generation);
  if(!key.value().equals(asset.get("object_key")))throw new IllegalStateException("Invalid stored object identity");
  var signed=signer.sign(key);var result=new LinkedHashMap<String,Object>();result.put("user_id",owner.toString());result.put("recording_id",recording.toString());result.put("generation",generation.toString());result.put("sha256",asset.get("sha256"));result.put("size_bytes",asset.get("verified_size"));result.put("cloud_revision",asset.get("cloud_revision"));result.put("url",signed.url());result.put("expires_at",signed.expiresAt().toString());return result;
 }
}
