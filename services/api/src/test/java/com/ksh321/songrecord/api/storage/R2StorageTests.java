package com.ksh321.songrecord.api.storage;

import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class R2StorageTests {
    MockEnvironment environment(String name,String role){
        String prefix="songrecord.storage."+name+".";
        return new MockEnvironment().withProperty("songrecord.storage.enabled","true")
            .withProperty("songrecord.storage.environment",name).withProperty("songrecord.storage.role",role)
            .withProperty(prefix+"account-id","a".repeat(32)).withProperty(prefix+"temporary-bucket","song-record-"+name+"-temporary")
            .withProperty(prefix+"final-bucket","song-record-"+name+"-final")
            .withProperty(prefix+role+".access-key","fixture-access").withProperty(prefix+role+".secret-key","fixture-secret");
    }
    @Test void defaultsDoNotConnectAndEnablingWithoutConfigurationFailsClosed(){
        try(var c=new AnnotationConfigApplicationContext()){c.register(R2StorageConfiguration.class);c.refresh();assertThat(c.getBeansOfType(R2Storage.class)).isEmpty();}
        assertThatThrownBy(()->R2Settings.from(new MockEnvironment())).isInstanceOf(IllegalStateException.class);
    }
    @Test void environmentAndRoleNeverFallBackToOtherCredentials(){
        var e=environment("dev","api");e.setProperty("songrecord.storage.environment","prod");
        assertThatThrownBy(()->R2Settings.from(e)).isInstanceOf(IllegalStateException.class);
        e.setProperty("songrecord.storage.environment","dev");e.setProperty("songrecord.storage.role","worker");
        assertThatThrownBy(()->R2Settings.from(e)).isInstanceOf(IllegalStateException.class);
        var wrong=environment("prod","worker");wrong.setProperty("songrecord.storage.prod.final-bucket","song-record-dev-final");assertThatThrownBy(()->R2Settings.from(wrong)).isInstanceOf(IllegalStateException.class);
    }
    @Test void credentialsAndEndpointAreNeverLogged(){
        var settings=R2Settings.from(environment("dev","api"));
        assertThat(settings.toString()).isEqualTo("R2Settings[REDACTED]");
        var e=environment("dev","api");e.setProperty("songrecord.storage.dev.account-id","secret-invalid-account");
        assertThatThrownBy(()->R2Settings.from(e)).hasMessageNotContaining("secret-invalid-account");
        var client=mock(S3Client.class);
        doThrow(new IllegalStateException("secret-provider-url")).when(client).headBucket(any(java.util.function.Consumer.class));
        try(var storage=new R2Storage(settings,client)){
            assertThatThrownBy(storage::verifyConnection).hasMessageNotContaining("secret-provider-url").hasNoCause();
            assertThat(storage.toString()).isEqualTo("R2Storage[REDACTED]");
        }
    }
    @Test void apiCanCheckTemporaryBucketButCannotAcquireFinalWriter(){
        var client=mock(S3Client.class);
        try(var storage=new R2Storage(R2Settings.from(environment("dev","api")),client)){
            storage.verifyConnection();verify(client,times(1)).headBucket(any(java.util.function.Consumer.class));
            assertThatThrownBy(storage::finalWriterBucket).isInstanceOf(IllegalStateException.class);
        }
        verify(client).close();
    }
    @Test void workerChecksBothPrivateBucketsAndSpringClosesClient(){
        var client=mock(S3Client.class);
        try(var storage=new R2Storage(R2Settings.from(environment("prod","worker")),client)){
            storage.verifyConnection();verify(client,times(2)).headBucket(any(java.util.function.Consumer.class));
            assertThat(storage.finalWriterBucket()).isEqualTo("song-record-prod-final");
        }
        try(var c=new AnnotationConfigApplicationContext()){
            c.setEnvironment(environment("dev","worker"));c.register(R2StorageConfiguration.class);c.refresh();
            assertThat(c.getBean(R2Storage.class).finalWriterBucket()).isEqualTo("song-record-dev-final");
        }
    }
    @Test void objectKeysBindOwnerRecordingAttemptAndGenerationWithoutClientPaths(){
        UUID owner=UUID.randomUUID(),recording=UUID.randomUUID(),attempt=UUID.randomUUID(),generation=UUID.randomUUID();
        var temp=new StorageObjectKeys.Temporary(owner,recording,attempt);
        var target=new StorageObjectKeys.Final(owner,recording,generation);
        assertThat(temp.value()).isEqualTo("temporary/"+owner+"/"+recording+"/"+attempt);
        assertThat(target.value()).isEqualTo("recordings/"+owner+"/"+recording+"/"+generation+".m4a");
        assertThat(new StorageObjectKeys.Temporary(owner,recording,UUID.randomUUID()).value()).isNotEqualTo(temp.value());
        assertThat(new StorageObjectKeys.Final(owner,recording,UUID.randomUUID()).value()).isNotEqualTo(target.value());
        assertThat(new StorageObjectKeys.Temporary(UUID.randomUUID(),recording,attempt).value()).isNotEqualTo(temp.value());
        assertThatThrownBy(()->new StorageObjectKeys.Final(owner,recording,new UUID(0,0))).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->new StorageObjectKeys.Temporary(null,recording,attempt)).isInstanceOf(NullPointerException.class);
    }
    @Test void readProbeSeparatesForbiddenMissingAndTransportErrorsWithoutProviderText(){
        var client=mock(S3Client.class);
        when(client.listObjectsV2(any(java.util.function.Consumer.class)))
            .thenReturn(ListObjectsV2Response.builder().build())
            .thenThrow(S3Exception.builder().statusCode(403).message("private-provider-text").build())
            .thenThrow(S3Exception.builder().statusCode(404).message("private-provider-text").build())
            .thenThrow(new IllegalStateException("private-provider-text"));
        try(var storage=new R2Storage(R2Settings.from(environment("dev","api")),client)){
            assertThat(storage.checkBucketRead("song-record-dev-temporary")).isEqualTo("ALLOWED");
            assertThat(storage.checkBucketRead("song-record-dev-final")).isEqualTo("DENIED");
            assertThat(storage.checkBucketRead("song-record-prod-final")).isEqualTo("MISSING");
            assertThat(storage.checkBucketRead("song-record-prod-temporary")).isEqualTo("ERROR");
            assertThatThrownBy(()->storage.checkBucketRead("other-bucket")).isInstanceOf(IllegalArgumentException.class);
        }
    }

}
