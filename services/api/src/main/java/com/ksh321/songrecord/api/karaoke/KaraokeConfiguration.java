package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.Clock;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class KaraokeConfiguration {
    @Bean MananaSearchAdapter mananaSearchAdapter(){return new MananaSearchAdapter();}
    @Bean SourceTokens sourceTokens(@Value("${songrecord.karaoke.key-base64:}")String encoded){try{return new SourceTokens(encoded.isBlank()?null:Base64.getDecoder().decode(encoded),Clock.systemUTC());}catch(IllegalArgumentException e){throw new IllegalStateException("Karaoke requires a valid independent 32-byte Base64 key");}}
    @Bean SearchLimit searchLimit(){return new SearchLimit(Clock.systemUTC());}
    @Bean KaraokeSearch karaokeSearch(AccountAccess access,SearchLimit limit,MananaSearchAdapter provider){return new KaraokeSearch(access,limit,provider::search);}
    @Bean KaraokeResults karaokeResults(AccountAccess access,KaraokeSearch search,SourceTokens tokens,JdbcTemplate jdbc){return new KaraokeResults(access,search,tokens,(owner,numbers)->{
        var args=new ArrayList<Object>();args.add(com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner));args.addAll(numbers);
        var sql="SELECT tj_number,id FROM song WHERE user_id=? AND source_type='TJ' AND lifecycle_state='ACTIVE' AND tj_number IN ("+String.join(",",Collections.nCopies(numbers.size(),"?"))+")";
        var matched=new HashMap<String,UUID>();jdbc.query(sql,(org.springframework.jdbc.core.RowCallbackHandler)rs->matched.put(rs.getString("tj_number"),com.ksh321.songrecord.api.songs.SongQueryKeys.uuid(rs.getBytes("id"))),args.toArray());return matched;});}
    @Bean @Order(2) SecurityFilterChain karaokeSecurity(HttpSecurity http)throws Exception{http.securityMatcher("/v1/karaoke/**").csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable()).authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/karaoke/search").permitAll().anyRequest().denyAll());return http.build();}
}
