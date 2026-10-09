package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class MananaSearchAdapterTests {
    @Test void selectedBrandPathsPreserveZerosOriginalParenthesesAndEncodedQuery() throws Exception {
        var paths=new ArrayList<String>();var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",x->{paths.add(x.getRequestURI().getRawPath());var brand=x.getRequestURI().getPath().endsWith("/tj.json")?"tj":"kumyoung";var bytes=("[{\"brand\":\""+brand+"\",\"no\":\"00123\",\"title\":\"원본 (LIVE)\",\"singer\":\"가수\"}]").getBytes(StandardCharsets.UTF_8);x.sendResponseHeaders(200,bytes.length);x.getResponseBody().write(bytes);x.close();});server.start();
        try {
            var adapter=new MananaSearchAdapter(URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/"),Duration.ofSeconds(3));
            var title=adapter.search(Brand.TJ,MananaSearchAdapter.Kind.TITLE," 곡 /? . ").getFirst();
            assertThat(title.number()).isEqualTo("00123");assertThat(title.title()).isEqualTo("원본 (LIVE)");
            adapter.search(Brand.KY,MananaSearchAdapter.Kind.ARTIST,"가수");adapter.search(Brand.TJ,MananaSearchAdapter.Kind.NUMBER," 00123 ");
            assertThat(paths).hasSize(3);assertThat(paths.get(0)).contains("/song/","%2F%3F","%2E").endsWith("/tj.json");assertThat(paths.get(1)).endsWith("/kumyoung.json");assertThat(paths.get(2)).isEqualTo("/karaoke/no/00123/tj.json");
            assertThatThrownBy(()->adapter.search(Brand.TJ,MananaSearchAdapter.Kind.NUMBER,"1/2")).isInstanceOf(IllegalArgumentException.class);assertThat(paths).hasSize(3);
        } finally {server.stop(0);}
    }
    @Test void emptyArrayIsSuccessButWrongBrandInvalidJsonAndRedirectAreFailures() throws Exception {
        var responses=List.of("[]","[{\"brand\":\"kumyoung\",\"no\":\"1\",\"title\":\"곡\",\"singer\":\"가수\"}]","not-json");var index=new int[]{0};
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.createContext("/",x->{int i=index[0]++;var bytes=(i<3?responses.get(i):"[]").getBytes(StandardCharsets.UTF_8);if(i==3)x.getResponseHeaders().set("Location","https://api.manana.kr/");x.sendResponseHeaders(i==3?302:200,bytes.length);x.getResponseBody().write(bytes);x.close();});server.start();
        try {var adapter=new MananaSearchAdapter(URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/"),Duration.ofSeconds(3));assertThat(adapter.search(Brand.TJ,MananaSearchAdapter.Kind.TITLE,"곡")).isEmpty();for(int i=0;i<3;i++)assertThatThrownBy(()->adapter.search(Brand.TJ,MananaSearchAdapter.Kind.TITLE,"곡")).isInstanceOf(MananaSearchAdapter.ProviderFailure.class);assertThat(index[0]).isEqualTo(4);} finally {server.stop(0);}
    }
    @Test void elapsedBodyTimeoutAndOversizeHaveSpecificFailureKinds()throws Exception {
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        server.setExecutor(java.util.concurrent.Executors.newCachedThreadPool());
        server.createContext("/",x->{try{if(x.getRequestURI().getPath().contains("/slow/")){x.sendResponseHeaders(200,0);Thread.sleep(250);x.getResponseBody().write("[]".getBytes());}else{var bytes=new byte[2*1024*1024+1];java.util.Arrays.fill(bytes,(byte)' ');x.sendResponseHeaders(200,bytes.length);x.getResponseBody().write(bytes);}}catch(Exception ignored){}finally{x.close();}});server.start();
        try {
            var base=URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/");
            assertThatThrownBy(()->new MananaSearchAdapter(base,Duration.ofMillis(80)).search(Brand.TJ,MananaSearchAdapter.Kind.TITLE,"slow")).isInstanceOfSatisfying(MananaSearchAdapter.ProviderFailure.class,e->assertThat(e.kind()).isEqualTo(MananaSearchAdapter.Failure.TIMEOUT));
            assertThatThrownBy(()->new MananaSearchAdapter(base,Duration.ofSeconds(3)).search(Brand.TJ,MananaSearchAdapter.Kind.TITLE,"large")).isInstanceOfSatisfying(MananaSearchAdapter.ProviderFailure.class,e->assertThat(e.kind()).isEqualTo(MananaSearchAdapter.Failure.INVALID_RESPONSE));
        }finally{server.stop(0);((java.util.concurrent.ExecutorService)server.getExecutor()).shutdownNow();}
    }

}
