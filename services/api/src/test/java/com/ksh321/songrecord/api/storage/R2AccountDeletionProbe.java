package com.ksh321.songrecord.api.storage;
/** Only fresh synthetic dev owners, sealed stdin credentials, closed result labels. */
public final class R2AccountDeletionProbe {
 public static void main(String[] args){var report=System.out;System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));System.setErr(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
  try{byte[] input=System.in.readNBytes(16385);if(input.length>16384)throw new IllegalArgumentException();var props=new java.util.Properties();props.load(new java.io.StringReader(new String(input,java.nio.charset.StandardCharsets.UTF_8)));java.util.Arrays.fill(input,(byte)0);
   if(!"dev".equals(props.getProperty("songrecord.storage.environment"))||!"worker".equals(props.getProperty("songrecord.storage.role")))throw new IllegalArgumentException();
   var env=new org.springframework.core.env.StandardEnvironment();env.getPropertySources().addFirst(new org.springframework.core.env.PropertiesPropertySource("private-input",props));var settings=R2Settings.from(env);
   try(var storage=new R2StorageConfiguration().r2Storage(env);var client=software.amazon.awssdk.services.s3.S3Client.builder().endpointOverride(settings.endpoint).region(software.amazon.awssdk.regions.Region.of("auto")).credentialsProvider(software.amazon.awssdk.auth.credentials.StaticCredentialsProvider.create(software.amazon.awssdk.auth.credentials.AwsBasicCredentials.create(settings.accessKey,settings.secretKey))).serviceConfiguration(software.amazon.awssdk.services.s3.S3Configuration.builder().pathStyleAccessEnabled(true).chunkedEncodingEnabled(false).build()).overrideConfiguration(c->c.apiCallTimeout(java.time.Duration.ofSeconds(20))).build()){
    com.ksh321.songrecord.api.auth.AccountDeletionWorkerTests.verifyReal(storage,key->client.putObject(r->r.bucket(settings.temporaryBucket).key(key.value()),software.amazon.awssdk.core.sync.RequestBody.fromBytes(new byte[]{1,2,3})));
   }props.clear();report.println("account-delete.scope=VERIFIED");
  }catch(Throwable unavailable){report.println("account-delete.scope=ERROR");System.exit(2);}
 }
}
