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
    public String temporaryBucket(){return settings.temporaryBucket;}
    // API-role processes cannot request the final writer's bucket through this boundary.
    public String finalWriterBucket(){if(!settings.role.equals("worker"))throw new IllegalStateException("Final storage requires worker role");return settings.finalBucket;}
    @Override public void close(){client.close();}
    @Override public String toString(){return "R2Storage[REDACTED]";}
}
