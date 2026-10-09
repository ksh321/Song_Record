package com.ksh321.songrecord.api.storage;

/** Dev-only synthetic transport fixture; production authorization is tested separately. */
public final class R2PlaybackFixture {
 public static void main(String[] args) {
  var output=System.out;System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));System.setErr(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
  try {
   byte[] input=System.in.readNBytes(16385);if(input.length>16384)throw new IllegalArgumentException();
   var props=new java.util.Properties();props.load(new java.io.StringReader(new String(input,java.nio.charset.StandardCharsets.UTF_8)));java.util.Arrays.fill(input,(byte)0);
   if(!"dev".equals(props.getProperty("songrecord.storage.environment")))throw new IllegalArgumentException();
   var bytes=java.nio.file.Files.readAllBytes(java.nio.file.Path.of(props.getProperty("diagnostic.audio-file")));
   if(bytes.length<1||bytes.length>6291456)throw new IllegalArgumentException();
   var hash=java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes));
   var env=new org.springframework.core.env.StandardEnvironment();env.getPropertySources().addFirst(new org.springframework.core.env.PropertiesPropertySource("private",props));props.setProperty("songrecord.storage.role","worker");
   var owner=java.util.UUID.fromString("00000000-0000-4000-8000-000000001401");var recording=java.util.UUID.fromString("00000000-0000-4000-8000-000000001403");
   var key=new StorageObjectKeys.Final(owner,recording,java.util.UUID.randomUUID());
   var server=com.sun.net.httpserver.HttpServer.create(new java.net.InetSocketAddress("127.0.0.1",46414),0);
   try(var storage=new R2StorageConfiguration().r2Storage(env);var signer=new R2StorageConfiguration().r2GetSigner(env)) {
    if(storage.existsFinal(key))throw new IllegalStateException();boolean created=false;
    try {
     created=true;storage.ensureFinal(key,java.nio.ByteBuffer.wrap(bytes),hash);
     server.createContext("/v1/recordings/"+recording+"/playback-url",exchange->{
      try {
       if(!"POST".equals(exchange.getRequestMethod())||!"Bearer synthetic-playback".equals(exchange.getRequestHeaders().getFirst("Authorization"))||!exchange.getRequestURI().getPath().equals("/v1/recordings/"+recording+"/playback-url")){exchange.sendResponseHeaders(403,-1);return;}
       var signed=signer.sign(key);var body=new tools.jackson.databind.ObjectMapper().writeValueAsBytes(java.util.Map.of("user_id",owner.toString(),"recording_id",recording.toString(),"generation",key.generation().toString(),"sha256",hash,"size_bytes",bytes.length,"cloud_revision",1,"url",signed.url(),"expires_at",signed.expiresAt().toString()));
       exchange.getResponseHeaders().set("Content-Type","application/json");exchange.getResponseHeaders().set("Cache-Control","no-store");exchange.sendResponseHeaders(200,body.length);exchange.getResponseBody().write(body);
      }catch(Exception failure){exchange.sendResponseHeaders(503,-1);}finally{exchange.close();}
     });
     var finish=new java.util.concurrent.CountDownLatch(1);
     server.createContext("/stop",exchange->{try{if("POST".equals(exchange.getRequestMethod())&&"Bearer synthetic-playback".equals(exchange.getRequestHeaders().getFirst("Authorization"))){exchange.sendResponseHeaders(204,-1);finish.countDown();}else exchange.sendResponseHeaders(403,-1);}finally{exchange.close();}});
     server.start();output.println("fixture=READY");output.flush();
     finish.await(45,java.util.concurrent.TimeUnit.MINUTES);
    }finally{server.stop(0);if(created&&storage.existsFinal(key)){storage.deleteFinal(key);if(storage.existsFinal(key))throw new IllegalStateException();}}
   }finally{server.stop(0);props.clear();}
   output.println("fixture=CLOSED");
  }catch(Throwable failure){output.println("fixture=FAIL");System.exit(2);}
 }
}
