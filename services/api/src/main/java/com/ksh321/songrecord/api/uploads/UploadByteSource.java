package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import java.io.InputStream;
/** Server-owned typed key only; never accept a URL or path from a job payload. */
@FunctionalInterface public interface UploadByteSource {
    InputStream open(StorageObjectKeys.Temporary key);
}
