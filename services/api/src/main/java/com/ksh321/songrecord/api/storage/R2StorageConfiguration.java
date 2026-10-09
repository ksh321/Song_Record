package com.ksh321.songrecord.api.storage;

import java.time.Duration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import software.amazon.awssdk.auth.credentials.*;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.*;

@Configuration(proxyBeanMethods=false)
@ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
public class R2StorageConfiguration {
    @Bean(destroyMethod="close") R2PutSigner r2PutSigner(Environment environment){
        var s=R2Settings.from(environment);
        var signer=software.amazon.awssdk.services.s3.presigner.S3Presigner.builder().endpointOverride(s.endpoint).region(Region.of("auto"))
            .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(s.accessKey,s.secretKey)))
            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build()).build();
        return new R2PutSigner(signer,s.temporaryBucket,java.time.Clock.systemUTC());
    }
    @Bean(destroyMethod="close") R2GetSigner r2GetSigner(Environment environment){
        var s=R2Settings.from(environment);
        var signer=software.amazon.awssdk.services.s3.presigner.S3Presigner.builder().endpointOverride(s.endpoint).region(Region.of("auto"))
            .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(s.accessKey,s.secretKey)))
            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build()).build();
        return new R2GetSigner(signer,s.finalBucket);
    }
    @Bean(destroyMethod="close") R2Storage r2Storage(Environment environment){
        var settings=R2Settings.from(environment);
        var client=S3Client.builder().endpointOverride(settings.endpoint).region(Region.of("auto"))
            .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(settings.accessKey,settings.secretKey)))
            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).chunkedEncodingEnabled(false).build())
            .httpClientBuilder(UrlConnectionHttpClient.builder().connectionTimeout(Duration.ofSeconds(5)).socketTimeout(Duration.ofSeconds(10)))
            .overrideConfiguration(c->c.apiCallTimeout(Duration.ofSeconds(20)).apiCallAttemptTimeout(Duration.ofSeconds(10))).build();
        return new R2Storage(settings,client);
    }
}
