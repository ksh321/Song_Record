package com.ksh321.songrecord.api.auth;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class KakaoHttpTokenInfoClientTests {
    private HttpServer server;
    private java.util.concurrent.ExecutorService executor;
    private URI endpoint;

    @BeforeEach
    void setup() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        executor = Executors.newCachedThreadPool();
        server.setExecutor(executor);
        endpoint = URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/token-info");
        server.start();
    }

    @AfterEach
    void cleanup() { server.stop(0); executor.shutdownNow(); }

    @Test
    void sendsBearerOnlyInHeaderAndKeepsStatusAndBody() throws Exception {
        AtomicReference<String> auth = new AtomicReference<>();
        AtomicReference<String> methodAndUri = new AtomicReference<>();
        server.createContext("/token-info", e -> {
            auth.set(e.getRequestHeaders().getFirst("Authorization"));
            methodAndUri.set(e.getRequestMethod() + " " + e.getRequestURI());
            e.sendResponseHeaders(401, 2); e.getResponseBody().write("{}".getBytes()); e.close();
        });
        try (var client = new KakaoHttpTokenInfoClient(endpoint, Duration.ofSeconds(2))) {
            var response = client.retrieve("private-token");
            assertEquals(401, response.status());
            assertEquals("{}", new String(response.body()));
            assertEquals("Bearer private-token", auth.get());
            assertEquals("GET /token-info", methodAndUri.get());
            assertFalse(response.toString().contains("{}"));
        }
    }

    @Test
    void neverFollowsRedirectWithBearerToken() throws Exception {
        AtomicInteger redirected = new AtomicInteger();
        server.createContext("/target", e -> { redirected.incrementAndGet(); e.sendResponseHeaders(200, -1); e.close(); });
        server.createContext("/token-info", e -> {
            e.getResponseHeaders().add("Location", endpoint.resolve("/target").toString());
            e.sendResponseHeaders(302, -1); e.close();
        });
        try (var client = new KakaoHttpTokenInfoClient(endpoint, Duration.ofSeconds(2))) {
            assertEquals(302, client.retrieve("private-token").status());
            assertEquals(0, redirected.get());
        }
    }

    @Test
    void limitsResponseBodyWithoutTrustingContentLength() {
        server.createContext("/token-info", e -> {
            e.sendResponseHeaders(200, 0);
            try { e.getResponseBody().write(new byte[65_537]); } finally { e.close(); }
        });
        try (var client = new KakaoHttpTokenInfoClient(endpoint, Duration.ofSeconds(2))) {
            assertThrows(IOException.class, () -> client.retrieve("private-token"));
        }
    }

    @Test
    void timesOutEvenAfterHeadersArrive() {
        server.createContext("/token-info", e -> {
            e.sendResponseHeaders(200, 0);
            e.getResponseBody().write('{'); e.getResponseBody().flush();
            try { Thread.sleep(2000); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
            finally { e.close(); }
        });
        try (var client = new KakaoHttpTokenInfoClient(endpoint, Duration.ofMillis(200))) {
            assertThrows(IOException.class, () -> client.retrieve("private-token"));
        }
    }
}
