package com.ksh321.songrecord.api.auth;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;
import com.ksh321.songrecord.api.web.ApiException;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.http.HttpMethod;
import org.springframework.util.LinkedMultiValueMap;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.assertj.core.api.Assertions.assertThat;

/** Opt-in loopback bridge to real controllers and an ephemeral H2 test database.
 * No production configuration, provider login, user database or audio endpoint. */
class DeviceFlowHarnessTests {
    static final class Harness implements AutoCloseable {
        final TwoDeviceInformationFlowTests f = new TwoDeviceInformationFlowTests();
        final HttpServer server;
        final CountDownLatch stop = new CountDownLatch(1);
        Harness(int port) throws Exception {
            f.open();
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
            server.createContext("/", this::handle);
            server.start();
        }
        void reply(HttpExchange x, int status, Object body) throws Exception {
            byte[] bytes = f.json.writeValueAsString(body).getBytes(StandardCharsets.UTF_8);
            x.getResponseHeaders().set("Content-Type", "application/json");
            x.getResponseHeaders().set("Cache-Control", "no-store");
            x.sendResponseHeaders(status, bytes.length);
            x.getResponseBody().write(bytes);
        }
        synchronized void handle(HttpExchange x) {
            try {
                String path = x.getRequestURI().getPath();
                if (path.equals("/verification/session/A") || path.equals("/verification/session/B")) {
                    boolean a = path.endsWith("A");
                    reply(x,200,Map.of("owner",f.f.registration.userId(),
                        "device", a ? f.f.registration.deviceId() : f.second.deviceId(),
                        "access", a ? f.f.tokens.accessToken() : f.secondTokens.accessToken(),
                        "recording", f.fixture.setup.id));
                } else if (path.equals("/verification/stop") && x.getRequestMethod().equals("POST")) {
                    reply(x,200,Map.of("stopped",true)); stop.countDown();
                } else if (path.equals("/v1/sync/changes") && x.getRequestMethod().equals("GET")) {
                    var query = new LinkedMultiValueMap<String,String>();
                    for (String pair : x.getRequestURI().getRawQuery().split("&")) {
                        String[] parts=pair.split("=",2);
                        query.add(URLDecoder.decode(parts[0],StandardCharsets.UTF_8),URLDecoder.decode(parts[1],StandardCharsets.UTF_8));
                    }
                    reply(x,200,f.changes.get(x.getRequestHeaders().getFirst("Authorization"),
                        x.getRequestHeaders().getFirst("X-Device-Id"),query));
                } else if (path.startsWith("/v1/recordings") || path.equals("/v1/songs") || path.startsWith("/v1/songs/")) {
                    byte[] body=x.getRequestBody().readNBytes(65537);
                    if(body.length>65536){ reply(x,413,Map.of("error","too large")); return; }
                    var builder=request(HttpMethod.valueOf(x.getRequestMethod()),path).contentType("application/json").content(body);
                    for(String header:List.of("Authorization","X-Device-Id","Idempotency-Key")) {
                        String value=x.getRequestHeaders().getFirst(header);
                        if(value!=null)builder.header(header,value);
                    }
                    var response=f.fixture.setup.setup.mvc.perform(builder).andReturn().getResponse();
                    reply(x,response.getStatus(),f.json.readTree(response.getContentAsString()));
                } else reply(x,404,Map.of("error","unavailable"));
            } catch(ApiException e) {
                try { reply(x,e.status().value(),Map.of("error",Map.of("code",e.code(),"details",e.details()))); } catch(Exception ignored) {}
            } catch(Exception e) {
                try { reply(x,500,Map.of("error","verification failure")); } catch(Exception ignored) {}
            } finally { x.close(); }
        }
        public void close() throws Exception {server.stop(0); f.close();}
    }
    @Test void bridgeUsesTwoDistinctDeviceSessionsForSameAccountAndRejectsUnauthenticatedFeed() throws Exception {
        try(var h=new Harness(0)) {
            String base="http://127.0.0.1:"+h.server.getAddress().getPort();
            var client=HttpClient.newHttpClient();
            var a=h.f.json.readTree(client.send(HttpRequest.newBuilder(URI.create(base+"/verification/session/A")).GET().build(),HttpResponse.BodyHandlers.ofString()).body());
            var b=h.f.json.readTree(client.send(HttpRequest.newBuilder(URI.create(base+"/verification/session/B")).GET().build(),HttpResponse.BodyHandlers.ofString()).body());
            assertThat(a.get("owner")).isEqualTo(b.get("owner"));
            assertThat(a.get("device")).isNotEqualTo(b.get("device"));
            assertThat(client.send(HttpRequest.newBuilder(URI.create(base+"/v1/sync/changes?after_seq=0&limit=50")).GET().build(),HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(401);
        }
    }
    @Test void bridgeRoutesSongCreationAndPersonalEditThroughRealControllers() throws Exception {
        try (var h = new Harness(0)) {
            String base = "http://127.0.0.1:" + h.server.getAddress().getPort();
            var client = HttpClient.newHttpClient();
            String id = UUID.randomUUID().toString();
            var create = client.send(HttpRequest.newBuilder(URI.create(base + "/v1/songs"))
                .header("Authorization", "Bearer " + h.f.f.tokens.accessToken())
                .header("X-Device-Id", h.f.f.registration.deviceId().toString())
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(h.f.json.writeValueAsString(Map.of(
                    "id", id, "source_type", "TJ", "source_token", "valid", "note", "before"))))
                .build(), HttpResponse.BodyHandlers.ofString());
            assertThat(create.statusCode()).isEqualTo(201);
            var edit = client.send(HttpRequest.newBuilder(URI.create(base + "/v1/songs/" + id))
                .header("Authorization", "Bearer " + h.f.f.tokens.accessToken())
                .header("X-Device-Id", h.f.f.registration.deviceId().toString())
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .header("Content-Type", "application/json")
                .method("PATCH", HttpRequest.BodyPublishers.ofString(h.f.json.writeValueAsString(
                    Map.of("base_revision", 1, "note", "after"))))
                .build(), HttpResponse.BodyHandlers.ofString());
            assertThat(edit.statusCode()).isEqualTo(200);
            assertThat(h.f.json.readTree(edit.body()).get("note").asText()).isEqualTo("after");
        }
    }
    @Test @EnabledIfEnvironmentVariable(named="P10_DEVICE_SERVER",matches="true")
    void serveIsolatedDeviceVerification() throws Exception {
        try(var h=new Harness(19090)) {
            Path ready=Path.of("../../.local/workflow/p10-10-manual/device-server-ready.json");
            Files.writeString(ready,"{\"port\":19090,\"isolated\":true}");
            try {h.stop.await(45,TimeUnit.MINUTES);} finally {Files.deleteIfExists(ready);}
        }
    }
}
