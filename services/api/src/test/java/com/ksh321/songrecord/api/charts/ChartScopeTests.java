package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class ChartScopeTests {
    @Test void sixScopesMatchPublishedProviderContractEvenWithTurkishDefaultLocale(){
        var old=Locale.getDefault();Locale.setDefault(Locale.forLanguageTag("tr-TR"));
        try {
            var expected=Map.of("TJ/DAILY","tj/daily","TJ/WEEKLY","tj/weekly","TJ/MONTHLY","tj/monthly","KY/DAILY","kumyoung/daily","KY/WEEKLY","kumyoung/weekly","KY/MONTHLY","kumyoung/monthly");
            for(var entry:expected.entrySet()){
                var parts=entry.getKey().split("/");var scope=ChartScope.parse(parts[0],parts[1]);
                assertThat(scope.sourceUri().toString()).isEqualTo("https://api.manana.kr/karaoke/popular/"+entry.getValue()+".json");
            }
        }finally{Locale.setDefault(old);}
    }
    @Test void unsupportedBrandsCalendarMonthsAndApproximatePeriodsAreNotMappedToDefaults(){
        for(var brand:new String[]{null,"tj","kumyoung","JOYSOUND","","TJ "})assertThatThrownBy(()->ChartScope.parse(brand,"MONTHLY")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("VALIDATION_FAILED"));
        for(var period:new String[]{null,"monthly","2026-10","LAST_30_DAYS","YEARLY",""})assertThatThrownBy(()->ChartScope.parse("TJ",period)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("VALIDATION_FAILED"));
        assertThatThrownBy(()->new ChartScope(Brand.TJ,null)).isInstanceOf(ApiException.class);
        assertThat(ChartScope.PERIOD_NOTICE).contains("제공자 기준","미제공");
    }
}
