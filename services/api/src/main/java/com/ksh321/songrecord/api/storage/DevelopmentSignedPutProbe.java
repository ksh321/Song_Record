package com.ksh321.songrecord.api.storage;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
/** Explicit developer diagnostic. Never receives arbitrary buckets or object keys. */
final class DevelopmentSignedPutProbe {
    static String run(S3Client client,R2PutSigner signer){
        String bucket="song-record-dev-temporary";
        var key=new StorageObjectKeys.Temporary(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());
        boolean owned=false;String result="ERROR";
        try {
            client.putObject(r->r.bucket(bucket).key(key.value()).ifNoneMatch("*"),RequestBody.fromBytes(new byte[0]));owned=true;
            byte[] bytes="Song_Record P12-04 synthetic signed upload".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            Instant deadline=Instant.now().plusSeconds(86400);
            try(var http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build()){
                for(int i=0;i<2;i++){
                    var signed=signer.sign(key,deadline);
                    var request=HttpRequest.newBuilder(URI.create(signed.url())).timeout(Duration.ofSeconds(15)).PUT(HttpRequest.BodyPublishers.ofByteArray(bytes));
                    signed.headers().forEach((name,values)->{if(!name.equalsIgnoreCase("host"))values.forEach(v->request.header(name,v));});
                    int status=http.send(request.build(),HttpResponse.BodyHandlers.discarding()).statusCode();
                    if(status<200 || status>=300)return "PUT_FAILED";
                    byte[] actual=client.getObjectAsBytes(r->r.bucket(bucket).key(key.value())).asByteArray();
                    if(!Arrays.equals(actual,bytes))return "BYTES_MISMATCH";
                    if(signed.expiresAt().isAfter(deadline))return "EXPIRY_FAILED";
                }
            }
            result="VERIFIED";
        }catch(Exception ignored){result="ERROR";}
        finally {
            if(owned)try{client.deleteObject(r->r.bucket(bucket).key(key.value()));}catch(Exception ignored){return "CLEANUP_FAILED";}
        }
        return result;
    }
}
