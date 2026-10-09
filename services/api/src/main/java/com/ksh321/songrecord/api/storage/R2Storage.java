package com.ksh321.songrecord.api.storage;

import java.util.Objects;
import software.amazon.awssdk.services.s3.S3Client;

/** Connection boundary only. Upload authorization/signing and verified writes follow in P12-03/04/09. */
public final class R2Storage implements AutoCloseable {
    private final R2Settings settings;
    private final S3Client client;
    R2Storage(R2Settings settings,S3Client client){this.settings=Objects.requireNonNull(settings);this.client=Objects.requireNonNull(client);}
    public void verifyConnection(){
        try {
            client.headBucket(r->r.bucket(settings.temporaryBucket));
            if(settings.role.equals("worker"))client.headBucket(r->r.bucket(settings.finalBucket));
        }catch(RuntimeException e){throw new IllegalStateException("R2 connection check failed; credentials and bucket access require verification");}
    }
    public String checkBucketRead(String bucket) {
        if(!bucket.matches("song-record-(dev|prod)-(temporary|final)"))throw new IllegalArgumentException("Unsupported check target");
        try {client.listObjectsV2(r->r.bucket(bucket).maxKeys(1));return "ALLOWED";}
        catch(software.amazon.awssdk.services.s3.model.S3Exception e){return e.statusCode()==403?"DENIED":e.statusCode()==404?"MISSING":"ERROR";}
        catch(RuntimeException e){return "ERROR";}
    }
    // Explicit local diagnostic only: never writes to production or existing object keys.
    String checkDevelopmentWrite(String kind) {
        if (!settings.environment.equals("dev") || !kind.matches("temporary|final"))
            throw new IllegalArgumentException("Development probe only");
        return DevelopmentStorageProbe.run(client, settings.endpoint, "song-record-dev-" + kind);
    }
    String checkDevelopmentSignedPut(R2PutSigner signer){
        if(!settings.environment.equals("dev") || !settings.role.equals("api"))throw new IllegalArgumentException("Development API probe only");
        return DevelopmentSignedPutProbe.run(client,signer);
    }
    String checkDevelopmentAudio(com.ksh321.songrecord.api.uploads.AudioValidator validator,byte[] synthetic){
        if(!settings.environment.equals("dev") || !settings.role.equals("worker"))throw new IllegalArgumentException("Development worker probe only");
        return DevelopmentAudioProbe.run(client,this,validator,synthetic);
    }
    /** Streaming GET only in worker role; SDK connection/read/call timeouts remain bounded. */
    public java.io.InputStream openTemporary(StorageObjectKeys.Temporary key){
        com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();
        if(!settings.role.equals("worker"))throw new IllegalStateException("Upload reads require worker role");
        try{
            var response=client.getObject(software.amazon.awssdk.services.s3.model.GetObjectRequest.builder().bucket(settings.temporaryBucket).key(key.value()).build());
            // Abort instead of draining an oversized/untrusted response when the bounded reader stops.
            return new java.io.FilterInputStream(response){@Override public void close(){response.abort();}};
        }
        catch(RuntimeException e){throw new IllegalStateException("UPLOAD_BYTES_UNAVAILABLE");}
    }
    /** Conditional final write; an existing generation must contain exactly the same bytes. */
    public void ensureFinal(StorageObjectKeys.Final key,java.nio.ByteBuffer view,String hash)throws Exception{
        com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();String bucket=finalWriterBucket();
        byte[] bytes=new byte[view.remaining()];view.asReadOnlyBuffer().get(bytes);
        if(bytes.length<1 || bytes.length>6291456)throw new IllegalStateException("FILE_SIZE_MISMATCH");
        try{client.putObject(r->r.bucket(bucket).key(key.value()).ifNoneMatch("*").contentType("audio/mp4"),software.amazon.awssdk.core.sync.RequestBody.fromBytes(bytes));}
        catch(software.amazon.awssdk.services.s3.model.S3Exception e){if(e.statusCode()!=412 && e.statusCode()!=409)throw new java.io.IOException("FINAL_WRITE_FAILED");}
        var input=client.getObject(r->r.bucket(bucket).key(key.value()));try{
            byte[] actual=input.readNBytes(6291457);
            if(!java.util.Arrays.equals(bytes,actual))throw new java.io.IOException("FINAL_OBJECT_MISMATCH");
        }catch(java.io.IOException e){throw e;}catch(RuntimeException e){throw new java.io.IOException("FINAL_OBJECT_UNAVAILABLE");}finally{input.abort();}
    }
    public java.util.Optional<java.nio.ByteBuffer> readFinal(StorageObjectKeys.Final key)throws Exception{
        com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();
        try{var input=client.getObject(r->r.bucket(finalWriterBucket()).key(key.value()));try{byte[] data=input.readNBytes(6291457);if(data.length>6291456)throw new java.io.IOException("FINAL_OBJECT_MISMATCH");return java.util.Optional.of(java.nio.ByteBuffer.wrap(data).asReadOnlyBuffer());}finally{input.abort();}}
        catch(software.amazon.awssdk.services.s3.model.NoSuchKeyException e){return java.util.Optional.empty();}
        catch(software.amazon.awssdk.services.s3.model.S3Exception e){if(e.statusCode()==404)return java.util.Optional.empty();throw new java.io.IOException("FINAL_OBJECT_UNAVAILABLE");}
    }
    public void deleteTemporary(StorageObjectKeys.Temporary key){com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();finalWriterBucket();client.deleteObject(r->r.bucket(settings.temporaryBucket).key(key.value()));}
    public void deleteUncommittedFinal(StorageObjectKeys.Final key){com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();client.deleteObject(r->r.bucket(finalWriterBucket()).key(key.value()));}
    public String temporaryBucket(){return settings.temporaryBucket;}
    // API-role processes cannot request the final writer's bucket through this boundary.
    public String finalWriterBucket(){if(!settings.role.equals("worker"))throw new IllegalStateException("Final storage requires worker role");return settings.finalBucket;}
    @Override public void close(){client.close();}
    @Override public String toString(){return "R2Storage[REDACTED]";}
}
