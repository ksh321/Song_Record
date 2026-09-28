package com.ksh321.songrecord.api.pagination;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.*;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/** Required for live list endpoints. No default or process-random production key. */
@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class PaginationConfiguration {
    @Bean PageCursor pageCursor(@Value("${songrecord.pagination.key-base64:}") String encoded) {
        try { return new PageCursor(Base64.getDecoder().decode(encoded), Clock.systemUTC(), Duration.ofMinutes(30)); }
        catch (IllegalArgumentException e) { throw new IllegalStateException("Pagination requires a valid 32-byte Base64 key"); }
    }
    @Bean KeysetPages keysetPages(JdbcTemplate jdbc, AccountAccess access, PlatformTransactionManager manager, PageCursor cursors) {
        return new KeysetPages(jdbc, access, manager, cursors);
    }
}
