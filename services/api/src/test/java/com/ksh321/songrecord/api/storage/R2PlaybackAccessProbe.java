package com.ksh321.songrecord.api.storage;

/** Private dev-only synthetic GET check. Never emits credentials, URL or object key. */
public final class R2PlaybackAccessProbe {
    public static void main(String[] args) {
        var report=System.out;
        System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
        System.setErr(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));
        try {
            byte[] input=System.in.readNBytes(16385);if(input.length>16384)throw new IllegalArgumentException();
            var props=new java.util.Properties();props.load(new java.io.StringReader(new String(input,java.nio.charset.StandardCharsets.UTF_8)));
            java.util.Arrays.fill(input,(byte)0);
            if(!"dev".equals(props.getProperty("songrecord.storage.environment")))throw new IllegalArgumentException();
            byte[] data=java.nio.file.Files.readAllBytes(java.nio.file.Path.of(props.getProperty("diagnostic.audio-file")));
            if(data.length<1||data.length>6291456)throw new IllegalArgumentException();
            String hash=java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(data));
            var env=new org.springframework.core.env.StandardEnvironment();env.getPropertySources().addFirst(new org.springframework.core.env.PropertiesPropertySource("private-input",props));
            props.setProperty("songrecord.storage.role","worker");
            try(var storage=new R2StorageConfiguration().r2Storage(env)) {
                var key=new StorageObjectKeys.Final(java.util.UUID.randomUUID(),java.util.UUID.randomUUID(),java.util.UUID.randomUUID());
                if(storage.existsFinal(key))throw new IllegalStateException();
                boolean created=false;
                try {
                    created=true;storage.ensureFinal(key,java.nio.ByteBuffer.wrap(data),hash);
                    props.setProperty("songrecord.storage.role","api");
                    try(var signer=new R2StorageConfiguration().r2GetSigner(env)) {
                        var signed=signer.sign(key);
                        var request=java.net.http.HttpRequest.newBuilder(java.net.URI.create(signed.url()))
                            .timeout(java.time.Duration.ofSeconds(30)).GET().build();
                        var client=java.net.http.HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(10))
                            .followRedirects(java.net.http.HttpClient.Redirect.NEVER).build();
                        var response=client.send(request,java.net.http.HttpResponse.BodyHandlers.ofByteArray());
                        if(response.statusCode()==200&&java.util.Arrays.equals(response.body(),data))report.println("playback.api=VERIFIED");
                        else if(response.statusCode()==403)report.println("playback.api=DENIED");
                        else report.println("playback.api=ERROR");
                    }
                }finally {
                    if(created&&storage.existsFinal(key)){storage.deleteFinal(key);if(storage.existsFinal(key))throw new IllegalStateException();}
                }
            }
            props.clear();report.println("playback.cleanup=VERIFIED");
        }catch(Throwable error){report.println("playback.probe=ERROR");System.exit(2);}
    }
}
