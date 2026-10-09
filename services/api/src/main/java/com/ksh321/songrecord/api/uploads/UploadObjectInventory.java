package com.ksh321.songrecord.api.uploads;
import java.time.Instant;import java.nio.ByteBuffer;import java.util.Optional;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
public interface UploadObjectInventory {
 record Entry(String key,long size,Instant modified){public Entry{if(key==null || size<0 || modified==null)throw new IllegalArgumentException("Invalid object observation");}public String toString(){return "ObjectObservation[REDACTED]";}}
 @FunctionalInterface interface Visitor{void accept(Entry entry)throws Exception;}
 void temporaryObjects(Visitor visitor)throws Exception;
 void finalObjects(Visitor visitor)throws Exception;
 Optional<ByteBuffer> readFinal(StorageObjectKeys.Final key)throws Exception;
 void deleteTemporary(StorageObjectKeys.Temporary key)throws Exception;
 void deleteUncommittedFinal(StorageObjectKeys.Final key)throws Exception;
}
