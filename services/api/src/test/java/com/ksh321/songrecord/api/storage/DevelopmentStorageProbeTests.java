package com.ksh321.songrecord.api.storage;

import java.net.URI;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class DevelopmentStorageProbeTests {
    final URI endpoint=URI.create("https://example.invalid");
    S3Client successful(){
        var client=mock(S3Client.class);
        when(client.getObjectAsBytes(any(GetObjectRequest.class))).thenReturn(ResponseBytes.fromByteArray(GetObjectResponse.builder().build(),"Song_Record development connection check".getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        return client;
    }
    @Test void writesUniqueSyntheticObjectComparesBytesChecksAnonymousDenialAndCleansOnlyThatKey(){
        var client=successful();
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-temporary",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("VERIFIED");
        var put=ArgumentCaptor.forClass(PutObjectRequest.class);verify(client).putObject(put.capture(),any(RequestBody.class));
        var deleted=ArgumentCaptor.forClass(DeleteObjectRequest.class);verify(client).deleteObject(deleted.capture());
        assertThat(put.getValue().key()).matches("connection-check/[0-9a-f-]{36}\\.txt");
        assertThat(put.getValue().ifNoneMatch()).isEqualTo("*");
        assertThat(deleted.getValue().key()).isEqualTo(put.getValue().key());
        assertThat(deleted.getValue().bucket()).isEqualTo(put.getValue().bucket());
    }
    @Test void deniedPutDoesNotAttemptReadOrDelete(){
        var client=mock(S3Client.class);
        when(client.putObject(any(PutObjectRequest.class),any(RequestBody.class))).thenThrow(S3Exception.builder().statusCode(403).build());
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("DENIED");
        verify(client,never()).getObjectAsBytes(any(GetObjectRequest.class));verify(client,never()).deleteObject(any(DeleteObjectRequest.class));
    }
    @Test void deniedReadIsNotDeniedWriteAndStillCleans(){
        var client=mock(S3Client.class);
        when(client.getObjectAsBytes(any(GetObjectRequest.class))).thenThrow(S3Exception.builder().statusCode(403).build());
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("GET_HTTP_403");
        verify(client).deleteObject(any(DeleteObjectRequest.class));
    }
    @Test void collisionNeverDeletesExistingObjectAndProductionIsRejected(){
        var client=mock(S3Client.class);
        when(client.putObject(any(PutObjectRequest.class),any(RequestBody.class))).thenThrow(S3Exception.builder().statusCode(412).build());
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("PUT_HTTP_412");
        verify(client,never()).deleteObject(any(DeleteObjectRequest.class));
        assertThatThrownBy(()->DevelopmentStorageProbe.run(client,endpoint,"song-record-prod-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void publicAccessAndWrongBytesFailAndCleanupFailureCannotPass(){
        var client=successful();
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(200,false))).isEqualTo("ANONYMOUS_HTTP_200");
        when(client.getObjectAsBytes(any(GetObjectRequest.class))).thenReturn(ResponseBytes.fromByteArray(GetObjectResponse.builder().build(),"wrong".getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("BYTES_MISMATCH");
        when(client.deleteObject(any(DeleteObjectRequest.class))).thenThrow(new IllegalStateException("private"));
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("CLEANUP_FAILED");
    }
    @Test void ambiguousPutFailureAttemptsCleanupWithoutClaimingSuccess(){
        var client=mock(S3Client.class);
        when(client.putObject(any(PutObjectRequest.class),any(RequestBody.class))).thenThrow(new IllegalStateException("private"));
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(403,false))).isEqualTo("PUT_TRANSPORT_ERROR");
        verify(client).deleteObject(any(DeleteObjectRequest.class));
    }
    @Test void r2MissingAuthorization400IsRecognizedButOther400AndUnsafeXmlFail() {
        var client=successful();
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(400,true))).isEqualTo("VERIFIED");
        assertThat(DevelopmentStorageProbe.run(client,endpoint,"song-record-dev-final",uri->new DevelopmentStorageProbe.AnonymousResponse(400,false))).isEqualTo("ANONYMOUS_HTTP_400");
        String body="<Error><Code>InvalidArgument</Code><Message>Authorization</Message></Error>";
        assertThat(DevelopmentStorageProbe.missingAuthorization(body.getBytes())).isTrue();
        assertThat(DevelopmentStorageProbe.missingAuthorization(body.replace("Authorization","Other").getBytes())).isFalse();
        assertThat(DevelopmentStorageProbe.missingAuthorization(("<!DOCTYPE Error [<!ENTITY x SYSTEM 'file:///not-readable'>]>"+body).getBytes())).isFalse();
        assertThat(DevelopmentStorageProbe.missingAuthorization(new byte[4097])).isFalse();
    }
}
