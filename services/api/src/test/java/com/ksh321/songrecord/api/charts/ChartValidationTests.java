package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class ChartValidationTests {
    final ChartValidation validation=new ChartValidation();final ChartScope tj=new ChartScope(Brand.TJ,ChartScope.Period.MONTHLY);
    byte[] bytes(String s){return s.getBytes(StandardCharsets.UTF_8);}
    String row(String brand,String number){return "{\"brand\":\""+brand+"\",\"no\":\""+number+"\",\"title\":\"원본 (LIVE)\",\"singer\":\"검사 가수\"}";}
    @Test void allSixScopesPreserveOrderZerosOriginalTextAndOneBasedPosition(){
        for(var b:Brand.values())for(var p:ChartScope.Period.values()){
            var scope=new ChartScope(b,p);var items=validation.validate(scope,bytes("["+row(scope.providerBrand(),"002")+","+row(scope.providerBrand(),"001")+"]"));
            assertThat(items).hasSize(2);assertThat(items.getFirst()).isEqualTo(new ChartValidation.Item(1,"002","원본 (LIVE)","검사 가수"));assertThat(items.getLast().position()).isEqualTo(2);assertThat(items.getLast().number()).isEqualTo("001");
            assertThatThrownBy(()->items.clear()).isInstanceOf(UnsupportedOperationException.class);
        }
    }
    @Test void invalidTailDuplicateWrongBrandOrMissingFieldsRejectWholeArray(){
        for(String bad:List.of(row("kumyoung","1"),row("TJ","1"),row("tj","001"),row("tj","1").replace("\"no\":\"1\"","\"no\":1"),row("tj","1").replace("\"singer\":\"검사 가수\"","\"singer\":null"),row("tj","1").replace("원본 (LIVE)","  "),row("tj","１２"),row("tj","1".repeat(21)),"null","{}")){
            assertThatThrownBy(()->validation.validate(tj,bytes("["+row("tj","001")+","+bad+"]"))).isInstanceOf(ChartValidation.InvalidChart.class);
        }
    }
    @Test void truncatedJsonTrailingDocumentAndDuplicateFieldAreRejected(){
        for(String bad:List.of("[]","null","{}","["+row("tj","1"),"["+row("tj","1")+"] []","["+row("tj","1").replace("\"brand\":\"tj\"","\"brand\":\"tj\",\"brand\":\"tj\"")+"]")){
            assertThatThrownBy(()->validation.validate(tj,bytes(bad))).isInstanceOf(ChartValidation.InvalidChart.class);
        }
    }
    @Test void countIsNotHardcodedAndDifferentPeriodsMayHaveIdenticalItems(){
        var payload=bytes("["+row("tj","001")+"]");var monthly=validation.validate(tj,payload);
        assertThat(monthly).hasSize(1);assertThat(validation.validate(new ChartScope(Brand.TJ,ChartScope.Period.DAILY),payload)).isEqualTo(monthly);
        var many=new ArrayList<String>();for(int i=0;i<101;i++)many.add(row("tj",String.valueOf(i)));assertThat(validation.validate(tj,bytes("["+String.join(",",many)+"]"))).hasSize(101);
    }
    @Test void textLimitsRespectUnicodeCodePointsAndRejectUnpairedSurrogates(){
        assertThat(validation.validate(tj,bytes("["+row("tj","1").replace("원본 (LIVE)","😀".repeat(200))+"]"))).hasSize(1);
        assertThatThrownBy(()->validation.validate(tj,bytes("["+row("tj","1").replace("원본 (LIVE)","😀".repeat(201))+"]"))).isInstanceOf(ChartValidation.InvalidChart.class);
        assertThatThrownBy(()->validation.validate(tj,bytes("["+row("tj","1").replace("원본 (LIVE)","\\ud800")+"]"))).isInstanceOf(ChartValidation.InvalidChart.class);
    }
}
