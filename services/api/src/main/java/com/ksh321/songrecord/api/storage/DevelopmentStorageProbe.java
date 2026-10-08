package com.ksh321.songrecord.api.storage;

import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.Arrays;
import java.util.UUID;
import java.nio.charset.StandardCharsets;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

/** Opt-in local diagnostic. Only generated non-user objects in the two development buckets. */
final class DevelopmentStorageProbe {
    record AnonymousResponse(int status, boolean missingAuthorization) {}
    @FunctionalInterface interface AnonymousGet { AnonymousResponse status(URI uri) throws Exception; }
    static boolean missingAuthorization(byte[] body) {
        if(body.length>4096) return false;
        try {
            var factory=javax.xml.parsers.DocumentBuilderFactory.newInstance();
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities",false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
            factory.setXIncludeAware(false);factory.setExpandEntityReferences(false);
            var builder=factory.newDocumentBuilder();
            builder.setErrorHandler(new org.xml.sax.helpers.DefaultHandler());
            var root=builder.parse(new java.io.ByteArrayInputStream(body)).getDocumentElement();
            return root.getTagName().equals("Error") && root.getElementsByTagName("Code").getLength()==1
                && root.getElementsByTagName("Message").getLength()==1
                && root.getElementsByTagName("Code").item(0).getTextContent().equals("InvalidArgument")
                && root.getElementsByTagName("Message").item(0).getTextContent().equals("Authorization");
        }catch(Exception e){return false;}
    }
    static String run(S3Client client, URI endpoint, String bucket) {
        return run(client, endpoint, bucket, uri -> {
            try (var http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build()) {
                var response=http.send(HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(10)).GET().build(), HttpResponse.BodyHandlers.ofInputStream());
                try(var body=response.body()) {
                    return new AnonymousResponse(response.statusCode(), response.statusCode()==400 && missingAuthorization(body.readNBytes(4097)));
                }
            }
        });
    }
    static String run(S3Client client, URI endpoint, String bucket, AnonymousGet anonymous) {
        if (!bucket.matches("song-record-dev-(temporary|final)")) throw new IllegalArgumentException("Development bucket only");
        String key="connection-check/"+UUID.randomUUID()+".txt";
        byte[] bytes="Song_Record development connection check".getBytes(StandardCharsets.UTF_8);
        String result="ERROR", stage="PUT";
        boolean cleanup=false, putComplete=false;
        try {
            // The UUID namespace is owned by this diagnostic; clean up even after ambiguous PUT failure.
            cleanup=true;
            client.putObject(PutObjectRequest.builder().bucket(bucket).key(key).contentType("text/plain").ifNoneMatch("*").build(), RequestBody.fromBytes(bytes));
            putComplete=true; stage="GET";
            byte[] received=client.getObjectAsBytes(GetObjectRequest.builder().bucket(bucket).key(key).build()).asByteArray();
            if(!Arrays.equals(bytes,received)) result="BYTES_MISMATCH";
            else {
                stage="ANONYMOUS";
                var response=anonymous.status(URI.create(endpoint+"/"+bucket+"/"+key));
                result=response.status()==403 || (response.status()==400 && response.missingAuthorization())
                    ? "VERIFIED" : "ANONYMOUS_HTTP_"+response.status();
            }
        } catch(S3Exception e) {
            // A rejected PUT created no object. A later 403 is a failed read, not proof of denied PUT.
            result=stage+"_HTTP_"+e.statusCode();
            if(e.statusCode()==412 && !putComplete) cleanup=false;
            if(e.statusCode()==403) {
                if(!putComplete) {cleanup=false; result="DENIED";}
            }
        } catch(Exception e) { result=stage+"_TRANSPORT_ERROR"; }
        if(cleanup) {
            try {client.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(key).build());}
            catch(RuntimeException e) {return "CLEANUP_FAILED";}
        }
        return result;
    }
}
