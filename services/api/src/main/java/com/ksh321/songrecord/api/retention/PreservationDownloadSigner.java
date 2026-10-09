package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;import java.time.Instant;
public interface PreservationDownloadSigner {
 SignedGet sign(StorageObjectKeys.Final key);
 record SignedGet(String url,Instant expiresAt){public String toString(){return "SignedGet[REDACTED]";}}
}
