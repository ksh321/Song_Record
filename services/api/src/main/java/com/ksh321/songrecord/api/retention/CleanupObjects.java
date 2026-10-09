package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
/** A 404 in a verified owned bucket is absence; denied/network/unavailable is an exception. */
public interface CleanupObjects {boolean existsFinal(StorageObjectKeys.Final key)throws Exception;void deleteFinal(StorageObjectKeys.Final key)throws Exception;}
