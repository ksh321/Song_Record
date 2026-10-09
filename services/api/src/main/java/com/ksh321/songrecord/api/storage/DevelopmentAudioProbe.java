package com.ksh321.songrecord.api.storage;

import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.*;
import com.ksh321.songrecord.api.uploads.AudioValidator;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;

/** One-off synthetic development objects only; retains no keys, URLs, or audio reports. */
final class DevelopmentAudioProbe {
    static String run(S3Client client,R2Storage storage,AudioValidator validator,byte[] synthetic){
        String bucket="song-record-dev-temporary";
        var key=new StorageObjectKeys.Temporary(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());
        boolean owned=false;var finalKey=new StorageObjectKeys.Final(key.owner(),key.recording(),UUID.randomUUID());boolean finalOwned=false;
        try{
            if(synthetic.length<1 || synthetic.length>6*1024*1024)return "ERROR";
            client.putObject(r->r.bucket(bucket).key(key.value()).ifNoneMatch("*"),RequestBody.fromBytes(synthetic));owned=true;
            byte[] downloaded=download(storage,key);
            if(!Arrays.equals(downloaded,synthetic))return "BYTES_MISMATCH";
            var valid=validator.validate(ByteBuffer.wrap(downloaded),synthetic.length,hash(synthetic));
            // A later object overwrite must neither validate as audio nor change the captured result.
            byte[] corrupt=new byte[]{1,2,3,4};
            client.putObject(r->r.bucket(bucket).key(key.value()),RequestBody.fromBytes(corrupt));
            byte[] changed=download(storage,key);
            if(!Arrays.equals(changed,corrupt))return "BYTES_MISMATCH";
            try{validator.validate(ByteBuffer.wrap(changed),changed.length,hash(changed));return "VALIDATION_FAILED";}
            catch(AudioValidator.Invalid expected){if(!expected.code.equals("FILE_DECODE_FAILED") && !expected.code.equals("FILE_AUDIO_FORMAT"))return "VALIDATION_FAILED";}
            storage.ensureFinal(finalKey,valid.bytes(),valid.sha256());finalOwned=true;
            storage.ensureFinal(finalKey,valid.bytes(),valid.sha256());
            try{storage.ensureFinal(finalKey,ByteBuffer.wrap(corrupt),hash(corrupt));return "FINAL_OVERWRITE_ALLOWED";}catch(java.io.IOException expected){}
            try(var finalRead=client.getObject(r->r.bucket(storage.finalWriterBucket()).key(finalKey.value()))){if(!Arrays.equals(finalRead.readNBytes(synthetic.length+1),synthetic))return "FINAL_BYTES_MISMATCH";}
            byte[] preserved=new byte[valid.bytes().remaining()];valid.bytes().get(preserved);
            if(!Arrays.equals(preserved,synthetic))return "BYTES_MISMATCH";
            storage.deleteTemporary(key);owned=false;
            var recovered=storage.readFinal(finalKey).orElseThrow();validator.validate(recovered,synthetic.length,hash(synthetic));
            storage.deleteUncommittedFinal(finalKey);finalOwned=false;storage.deleteUncommittedFinal(finalKey);
            return storage.readFinal(finalKey).isEmpty()?"VERIFIED":"CLEANUP_FAILED";
        }catch(Exception ignored){return "ERROR";}
        finally{if(finalOwned)try{client.deleteObject(r->r.bucket(storage.finalWriterBucket()).key(finalKey.value()));}catch(Exception ignored){return "CLEANUP_FAILED";}if(owned)try{client.deleteObject(r->r.bucket(bucket).key(key.value()));}catch(Exception ignored){return "CLEANUP_FAILED";}}
    }
    private static byte[] download(R2Storage storage,StorageObjectKeys.Temporary key)throws Exception{
        try(var input=storage.openTemporary(key)){return input.readNBytes(6*1024*1024+1);}
    }
    private static String hash(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
}
