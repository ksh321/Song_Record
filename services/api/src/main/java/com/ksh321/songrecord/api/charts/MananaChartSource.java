package com.ksh321.songrecord.api.charts;

import java.net.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.Flow;
import static com.ksh321.songrecord.api.charts.ChartCollection.*;

/** Bounded read-only transport. Never registered for production persistence before terms approval. */
public final class MananaChartSource implements Source {
    private final URI base;private final HttpClient client;
    public MananaChartSource(){this(URI.create("https://api.manana.kr/"));}
    MananaChartSource(URI base){
        if(!base.equals(URI.create("https://api.manana.kr/")) && !("http".equals(base.getScheme()) && Set.of("localhost","127.0.0.1").contains(base.getHost()) && "/".equals(base.getPath()) && base.getUserInfo()==null && base.getQuery()==null && base.getFragment()==null))throw new IllegalArgumentException("Invalid chart origin");
        this.base=base;client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build();
    }
    public byte[] fetch(ChartScope scope,Duration remaining){
        if(remaining.isNegative() || remaining.isZero() || remaining.compareTo(Duration.ofSeconds(30))>0)throw new IllegalArgumentException("Invalid chart deadline");
        URI uri=base.resolve("karaoke/popular/"+scope.providerBrand()+"/"+scope.providerPeriod()+".json");
        var request=HttpRequest.newBuilder(uri).timeout(remaining).header("Accept","application/json").header("Cache-Control","no-store").GET().build();
        var future=client.sendAsync(request,info->new LimitedBody());
        try{var response=future.get(remaining.toNanos(),TimeUnit.NANOSECONDS);if(response.statusCode()!=200)throw new CollectionFailure(Failure.NETWORK);return response.body();}
        catch(TimeoutException e){throw new CollectionFailure(Failure.TIMEOUT);}
        catch(InterruptedException e){Thread.currentThread().interrupt();throw new CollectionFailure(Failure.TIMEOUT);}
        catch(ExecutionException e){if(e.getCause() instanceof CollectionFailure c)throw c;throw new CollectionFailure(e.getCause() instanceof HttpTimeoutException?Failure.TIMEOUT:Failure.NETWORK);}
        finally{future.cancel(true);}
    }
    private static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]>{
        final HttpResponse.BodySubscriber<byte[]> delegate=HttpResponse.BodySubscribers.ofByteArray();Flow.Subscription subscription;long count;
        public CompletionStage<byte[]> getBody(){return delegate.getBody();}
        public void onSubscribe(Flow.Subscription s){subscription=s;delegate.onSubscribe(s);}
        public void onNext(List<ByteBuffer> chunks){for(var b:chunks)count+=b.remaining();if(count>ChartStaging.MAX_BYTES){subscription.cancel();delegate.onError(new CollectionFailure(Failure.INVALID_RESPONSE));}else delegate.onNext(chunks);}
        public void onError(Throwable t){delegate.onError(t);}public void onComplete(){delegate.onComplete();}
    }
}
