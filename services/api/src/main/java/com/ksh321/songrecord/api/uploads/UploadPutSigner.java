package com.ksh321.songrecord.api.uploads;
import java.time.*;
import java.util.*;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
/** Local cryptographic signing only: implementations must not make network calls. */
public interface UploadPutSigner {
    SignedPut sign(StorageObjectKeys.Temporary key, Instant attemptExpiry);
    record SignedPut(String url, Instant expiresAt, Map<String,List<String>> headers) {
        public SignedPut { headers=Map.copyOf(headers); }
        @Override public String toString(){return "SignedPut[REDACTED]";}
    }
}
