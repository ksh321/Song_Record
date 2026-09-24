package com.ksh321.songrecord.api.auth;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Flow;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/** A dedicated client: no redirect following, cookies, wire logging, or automatic retries. */
final class KakaoHttpTokenInfoClient implements KakaoTokenInfoClient, AutoCloseable {
    static final int MAX_RESPONSE_BYTES = 65_536;
    private final HttpClient client;
    private final URI endpoint;
    private final Duration timeout;

    KakaoHttpTokenInfoClient() {
        this(URI.create("https://kapi.kakao.com/v1/user/access_token_info"), Duration.ofSeconds(5));
    }

    // Package-private seam for loopback HTTP tests; no user-controlled endpoint setting.
    KakaoHttpTokenInfoClient(URI endpoint, Duration timeout) {
        this.endpoint = endpoint;
        this.timeout = timeout;
        client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2))
                .followRedirects(HttpClient.Redirect.NEVER).build();
    }

    @Override
    public Response retrieve(String accessToken) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(endpoint).timeout(timeout)
                .header("Authorization", "Bearer " + accessToken)
                .header("Accept", "application/json").GET().build();
        var pending = client.sendAsync(request, info -> new LimitedBody());
        try {
            var response = pending.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            return new Response(response.statusCode(), response.body());
        } catch (TimeoutException | ExecutionException exception) {
            pending.cancel(true);
            throw new IOException("Kakao verification transport failed");
        } catch (InterruptedException exception) {
            pending.cancel(true);
            Thread.currentThread().interrupt();
            throw exception;
        }
    }

    @Override public void close() { client.shutdownNow(); }

    private static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
        private final CompletableFuture<byte[]> result = new CompletableFuture<>();
        private final ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        private Flow.Subscription subscription;

        @Override public CompletionStage<byte[]> getBody() { return result; }
        @Override public void onSubscribe(Flow.Subscription subscription) {
            this.subscription = subscription;
            subscription.request(1);
        }
        @Override public void onNext(List<ByteBuffer> buffers) {
            for (ByteBuffer buffer : buffers) {
                if (buffer.remaining() > MAX_RESPONSE_BYTES - bytes.size()) {
                    subscription.cancel();
                    result.completeExceptionally(new IOException("Provider response too large"));
                    return;
                }
                byte[] chunk = new byte[buffer.remaining()];
                buffer.get(chunk);
                bytes.writeBytes(chunk);
            }
            subscription.request(1);
        }
        @Override public void onError(Throwable error) {
            result.completeExceptionally(new IOException("Provider response failed"));
        }
        @Override public void onComplete() { result.complete(bytes.toByteArray()); }
    }
}
