package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.config.SecurityConfig;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.web.*;
import javax.sql.DataSource;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

class SnapshotHttpTests {
    AnnotationConfigWebApplicationContext context;MockMvc mvc;
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({SnapshotConfiguration.class,SnapshotController.class,SecurityConfig.class,GlobalExceptionHandler.class})
    static class Config {
        @Bean AccountAccess access(){return mock(AccountAccess.class);}
        @Bean JdbcTemplate jdbc(){return mock(JdbcTemplate.class);}
        @Bean DataSource source(){return mock(DataSource.class);}
        @Bean PlatformTransactionManager manager(){return mock(PlatformTransactionManager.class);}
        @Bean IdempotentMutations receipts(){return mock(IdempotentMutations.class);}
        @Bean JobQueue jobs(){return mock(JobQueue.class);}
    }
    @BeforeEach void setup(){
        context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());
        context.getEnvironment().setActiveProfiles("dev");
        context.getEnvironment().getPropertySources().addFirst(new org.springframework.core.env.MapPropertySource("fixture",Map.of("songrecord.pagination.key-base64",Base64.getEncoder().encodeToString(new byte[32]))));
        context.register(Config.class);context.refresh();mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        // Spring invokes JdbcTemplate.afterPropertiesSet during bean setup.
        // Verify request-time database interactions separately from lifecycle initialization.
        clearInvocations(context.getBean(JdbcTemplate.class));
    }
    @AfterEach void close(){context.close();}
    @Test void unauthenticatedEndpointsFailBeforeDatabaseAndOtherMethodsStayDenied() throws Exception {
        when(context.getBean(AccountAccess.class).authenticate(null,null)).thenThrow(new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","Authentication required",false,Map.of()));
        assertThat(mvc.perform(post("/v1/sync/snapshots").contentType("application/json").content("{\"schema_version\":1}")).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(mvc.perform(get("/v1/sync/snapshots/"+UUID.randomUUID())).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(mvc.perform(delete("/v1/sync/snapshots/"+UUID.randomUUID())).andReturn().getResponse().getStatus()).isEqualTo(403);
        assertThat(mvc.perform(get("/v1/sync/snapshots/a/b")).andReturn().getResponse().getStatus()).isEqualTo(403);
        verifyNoInteractions(context.getBean(JdbcTemplate.class),context.getBean(IdempotentMutations.class));
    }
    @Test void postForwardsExactReceiptAndNeverCreatesCookieSession() throws Exception {
        var account=mock(AccountAccess.Account.class);String op=UUID.randomUUID().toString();
        when(context.getBean(AccountAccess.class).authenticate("Bearer fixture","fixture-device")).thenReturn(account);
        when(context.getBean(IdempotentMutations.class).execute(eq(account),eq(op),eq("POST"),eq("/v1/sync/snapshots"),eq("{\"schema_version\":1}"),any()))
                .thenReturn(new IdempotentMutations.Reply(202,"{\"status\":\"BUILDING\"}"));
        var result=mvc.perform(post("/v1/sync/snapshots").header("Authorization","Bearer fixture").header("X-Device-Id","fixture-device").header("Idempotency-Key",op)
                .contentType("application/json").content("{\"schema_version\":1}")).andReturn();
        assertThat(result.getResponse().getStatus()).isEqualTo(202);assertThat(result.getResponse().getContentAsString()).isEqualTo("{\"status\":\"BUILDING\"}");
        assertThat(result.getResponse().getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(result.getResponse().getHeader("Set-Cookie")).isNull();assertThat(result.getRequest().getSession(false)).isNull();
        assertThat(context.getBeansOfType(JobQueue.class)).hasSize(1);
        assertThat(context.getBean(SnapshotWorker.class)).isNotNull();
    }
    @Test void malformedAndRepeatedParametersAreRejectedBeforeReadingData() throws Exception {
        when(context.getBean(AccountAccess.class).authenticate(null,null)).thenReturn(mock(AccountAccess.Account.class));
        assertThat(mvc.perform(get("/v1/sync/snapshots/invalid")).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(mvc.perform(get("/v1/sync/snapshots/"+UUID.randomUUID()).param("entity","SONG","TAG")).andReturn().getResponse().getStatus()).isEqualTo(400);
        verifyNoInteractions(context.getBean(JdbcTemplate.class));
    }
}
