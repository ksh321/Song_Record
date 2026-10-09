package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import java.nio.ByteBuffer;
/** Worker-only immutable final object boundary. Reads verify actual bytes, not metadata. */
public interface UploadFinalObjects {
    default java.util.Optional<ByteBuffer> read(StorageObjectKeys.Final key)throws Exception{return java.util.Optional.empty();}
    void ensure(StorageObjectKeys.Final key,ByteBuffer bytes,String sha256) throws Exception;
}
