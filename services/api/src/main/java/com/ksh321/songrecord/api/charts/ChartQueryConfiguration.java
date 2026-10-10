package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.karaoke.SourceTokens;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class ChartQueryConfiguration {
    @Bean ChartQuery chartQuery(JdbcTemplate jdbc,PlatformTransactionManager manager){return new ChartQuery(jdbc,manager);}
    @Bean ChartResults chartResults(AccountAccess access,ChartQuery query,SourceTokens tokens){return new ChartResults(access,query,tokens);}
    @Bean @Order(2) SecurityFilterChain chartSecurity(HttpSecurity http)throws Exception{http.securityMatcher("/v1/charts/**").csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable()).authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/charts/popular").permitAll().anyRequest().denyAll());return http.build();}
}
