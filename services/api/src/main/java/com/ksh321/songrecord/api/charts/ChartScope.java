package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.net.URI;
import java.util.*;
import org.springframework.http.HttpStatus;

/** D12 provider periods. These do not assert calendar boundaries, source freshness or ranks. */
public record ChartScope(Brand brand, Period period) {
    public enum Period { DAILY, WEEKLY, MONTHLY }
    public static final String PROVIDER="MANANA";
    public static final String PERIOD_NOTICE="제공자 기준 기간 · 정확 집계 날짜 미제공";
    public ChartScope {if(brand==null || period==null)throw invalid();}
    public static ChartScope parse(String brand,String period){
        try{return new ChartScope(Brand.valueOf(brand),Period.valueOf(period));}
        catch(IllegalArgumentException|NullPointerException e){throw invalid();}
    }
    public String providerBrand(){return brand==Brand.TJ?"tj":"kumyoung";}
    public String providerPeriod(){return period.name().toLowerCase(Locale.ROOT);}
    public URI sourceUri(){return URI.create("https://api.manana.kr/karaoke/popular/"+providerBrand()+"/"+providerPeriod()+".json");}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","차트 브랜드와 기간을 확인해 주세요.",false,Map.of());}
}
