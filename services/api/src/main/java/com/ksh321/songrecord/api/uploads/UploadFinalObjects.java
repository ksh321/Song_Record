package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import java.nio.ByteBuffer;
/** Worker-only immutable final object boundary. Reads verify actual bytes, not metadata. */
public interface UploadFinalObjects {
    void ensure(StorageObjectKeys.Final key,ByteBuffer bytes,String sha256) throws Exception;
}
