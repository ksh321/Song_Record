package com.ksh321.songrecord.api.storage;
import com.ksh321.songrecord.api.uploads.UploadPutSigner;
import java.time.*;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;
public final class R2PutSigner implements UploadPutSigner,AutoCloseable {
    private final S3Presigner signer;private final String bucket;private final Clock clock;
    R2PutSigner(S3Presigner signer,String bucket,Clock clock){this.signer=signer;this.bucket=bucket;this.clock=clock;}
    public SignedPut sign(StorageObjectKeys.Temporary key,Instant expiry){
        long seconds=Math.min(600,Duration.between(clock.instant(),expiry).getSeconds()-1);
        if(seconds<1)throw new IllegalStateException("Upload attempt expired");
        try {
        var signed=signer.presignPutObject(PutObjectPresignRequest.builder().signatureDuration(Duration.ofSeconds(seconds))
            .putObjectRequest(PutObjectRequest.builder().bucket(bucket).key(key.value()).build()).build());
        if(signed.expiration().isAfter(expiry))throw new IllegalStateException("Upload attempt expired during signing");
        return new SignedPut(signed.url().toExternalForm(),signed.expiration(),signed.signedHeaders());
        }catch(RuntimeException ignored){throw new IllegalStateException("Upload URL signing failed");}
    }
    public void close(){signer.close();}
    public String toString(){return "R2PutSigner[REDACTED]";}
}
