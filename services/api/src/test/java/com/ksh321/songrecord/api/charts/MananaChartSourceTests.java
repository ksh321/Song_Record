package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.sun.net.httpserver.HttpServer;
import java.net.*;import java.time.*;import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class MananaChartSourceTests {
    @Test void sixScopesUseExactPathsAndEntireBodyWithoutReordering()throws Exception{
        var paths=new ArrayList<String>();var raw="[{\"no\":\"002\"},{\"no\":\"001\"}]".getBytes();
        var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);server.createContext("/",x->{paths.add(x.getRequestURI().getPath());x.sendResponseHeaders(200,raw.length);x.getResponseBody().write(raw);x.close();});server.start();
        try{var source=new MananaChartSource(URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/"));for(var b:Brand.values())for(var p:ChartScope.Period.values()){var scope=new ChartScope(b,p);assertThat(source.fetch(scope,Duration.ofSeconds(2))).containsExactly(raw);assertThat(paths.getLast()).isEqualTo("/karaoke/popular/"+scope.providerBrand()+"/"+scope.providerPeriod()+".json");}assertThat(paths).hasSize(6);}finally{server.stop(0);}
    }
    @Test void timeoutOversizeAndRedirectNeverReturnPartialBodies()throws Exception{
        var calls=new java.util.concurrent.atomic.AtomicInteger();var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);var pool=java.util.concurrent.Executors.newCachedThreadPool();server.setExecutor(pool);
        server.createContext("/",x->{try{int i=calls.getAndIncrement();if(i==0){x.sendResponseHeaders(200,0);Thread.sleep(300);x.getResponseBody().write("[]".getBytes());}else if(i==1){byte[] large=new byte[ChartStaging.MAX_BYTES+1];x.sendResponseHeaders(200,large.length);x.getResponseBody().write(large);}else{x.getResponseHeaders().set("Location","https://api.manana.kr/");x.sendResponseHeaders(302,-1);}}catch(Exception ignored){}finally{x.close();}});server.start();
        try{var source=new MananaChartSource(URI.create("http://127.0.0.1:"+server.getAddress().getPort()+"/"));var scope=new ChartScope(Brand.TJ,ChartScope.Period.DAILY);
            assertThatThrownBy(()->source.fetch(scope,Duration.ofMillis(100))).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(ChartCollection.Failure.TIMEOUT));
            assertThatThrownBy(()->source.fetch(scope,Duration.ofSeconds(3))).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(ChartCollection.Failure.INVALID_RESPONSE));
            assertThatThrownBy(()->source.fetch(scope,Duration.ofSeconds(3))).isInstanceOf(ChartCollection.CollectionFailure.class);assertThat(calls).hasValue(3);
        }finally{server.stop(0);pool.shutdownNow();}
    }
}
