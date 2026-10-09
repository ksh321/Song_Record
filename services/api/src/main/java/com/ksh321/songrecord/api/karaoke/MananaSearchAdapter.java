package com.ksh321.songrecord.api.karaoke;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.Flow;

/** Selected-brand, bounded live queries only. No response cache or catalogue persistence. */
public final class MananaSearchAdapter {
    public enum Kind { TITLE, ARTIST, NUMBER }
    public enum Failure { TIMEOUT, NETWORK, PROVIDER_STATUS, INVALID_RESPONSE }
    public static final class ProviderFailure extends RuntimeException {
        private final Failure kind;
        ProviderFailure(Failure kind) { super("External search unavailable"); this.kind=kind; }
        public Failure kind(){ return kind; }
    }
    public record Candidate(Brand brand,String number,String title,String artist,String provider,String sourceRef) {
        @Override public String toString(){return "SearchCandidate[REDACTED]";}
    }
    private static final int MAX_BYTES=2*1024*1024;
    private final URI base;
    private final HttpClient client;
    private final Duration timeout;
    private final JsonMapper json=JsonMapper.builder().build();
    public MananaSearchAdapter(){this(URI.create("https://api.manana.kr/"),Duration.ofSeconds(3));}
    // Package-private injection is restricted to loopback test transports or the production origin.
    MananaSearchAdapter(URI base,Duration timeout){
        if (!base.equals(URI.create("https://api.manana.kr/")) && !("http".equals(base.getScheme()) && Set.of("localhost","127.0.0.1").contains(base.getHost()) && "/".equals(base.getPath()) && base.getUserInfo()==null && base.getQuery()==null && base.getFragment()==null)) throw new IllegalArgumentException("Invalid provider origin");
        if(timeout.isNegative() || timeout.isZero() || timeout.compareTo(Duration.ofSeconds(3))>0) throw new IllegalArgumentException("Invalid timeout");
        this.base=base;this.timeout=timeout;
        client=HttpClient.newBuilder().connectTimeout(timeout).followRedirects(HttpClient.Redirect.NEVER).build();
    }
    public List<Candidate> search(Brand brand,Kind kind,String input){
        Objects.requireNonNull(brand);Objects.requireNonNull(kind);
        var query=input==null?"":input.strip();
        if(query.isEmpty() || query.codePointCount(0,query.length())>200 || query.codePoints().anyMatch(c->Character.isISOControl(c)) || kind==Kind.NUMBER && !query.matches("[0-9]{1,20}")) throw new IllegalArgumentException("Invalid search query");
        var wire=brand==Brand.TJ?"tj":"kumyoung";
        var route=switch(kind){case TITLE->"song";case ARTIST->"singer";case NUMBER->"no";};
        var segment=URLEncoder.encode(query,StandardCharsets.UTF_8).replace("+","%20").replace(".","%2E");
        var uri=base.resolve("karaoke/"+route+"/"+segment+"/"+wire+".json");
        var request=HttpRequest.newBuilder(uri).timeout(timeout).header("Accept","application/json").header("Cache-Control","no-store").GET().build();
        var future=client.sendAsync(request,info->new LimitedBody());
        try {
            var response=future.get(timeout.toMillis(),TimeUnit.MILLISECONDS);
            if(response.statusCode()!=200) throw new ProviderFailure(Failure.PROVIDER_STATUS);
            var node=json.readTree(response.body());
            if(!node.isArray() || node.size()>1000) throw new ProviderFailure(Failure.INVALID_RESPONSE);
            var result=new ArrayList<Candidate>();var numbers=new HashSet<String>();
            for(var row:node){
                String number=text(row,"no"),title=text(row,"title"),artist=text(row,"singer");
                if(!wire.equals(text(row,"brand")) || !number.matches("[0-9]{1,20}") || title.isBlank() || artist.isBlank() || title.codePointCount(0,title.length())>200 || artist.codePointCount(0,artist.length())>200 || !numbers.add(number)) throw new ProviderFailure(Failure.INVALID_RESPONSE);
                result.add(new Candidate(brand,number,title,artist,"MANANA", "manana:"+wire+":"+number));
            }
            return List.copyOf(result);
        } catch(TimeoutException e){throw new ProviderFailure(Failure.TIMEOUT);}
          catch(InterruptedException e){Thread.currentThread().interrupt();throw new ProviderFailure(Failure.NETWORK);}
          catch(ExecutionException e){if(e.getCause() instanceof ProviderFailure failure) throw failure;throw new ProviderFailure(e.getCause() instanceof HttpTimeoutException ? Failure.TIMEOUT : Failure.NETWORK);}
          catch(ProviderFailure e){throw e;}
          catch(Exception e){throw new ProviderFailure(Failure.INVALID_RESPONSE);}
        finally {future.cancel(true);}
    }
    private String text(JsonNode row,String field){var v=row.get(field);if(v==null || !v.isString()) throw new ProviderFailure(Failure.INVALID_RESPONSE);return v.asString();}
    private static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
        final HttpResponse.BodySubscriber<byte[]> delegate=HttpResponse.BodySubscribers.ofByteArray();Flow.Subscription subscription;long bytes;
        public CompletionStage<byte[]> getBody(){return delegate.getBody();}
        public void onSubscribe(Flow.Subscription s){subscription=s;delegate.onSubscribe(s);}
        public void onNext(List<ByteBuffer> items){for(var b:items)bytes+=b.remaining();if(bytes>MAX_BYTES){subscription.cancel();delegate.onError(new ProviderFailure(Failure.INVALID_RESPONSE));}else delegate.onNext(items);}
        public void onError(Throwable t){delegate.onError(t);}
        public void onComplete(){delegate.onComplete();}
    }
}
