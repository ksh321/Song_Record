package com.ksh321.songrecord.api.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestIdFilterTests {

    private final RequestIdFilter filter = new RequestIdFilter();

    @Test
    void keepsPublicRequestIdAndLogsOnlyItsDigest() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        request.addHeader(RequestContext.REQUEST_ID_HEADER, "client-request-123");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<String> mdcValue = new AtomicReference<>();

        filter.doFilter(request, response, (ignoredRequest, ignoredResponse) ->
                mdcValue.set(MDC.get(RequestContext.REQUEST_ID_ATTRIBUTE)));

        assertThat(response.getHeader(RequestContext.REQUEST_ID_HEADER))
                .isEqualTo("client-request-123");
        assertThat(request.getAttribute(RequestContext.REQUEST_ID_ATTRIBUTE))
                .isEqualTo("client-request-123");
        assertThat(mdcValue.get()).isEqualTo("sha256:06d7f6015e13d0e3045a07d9d5d057561db2947a74a03b15c086e6d7e61538f7").doesNotContain("client-request-123");
        assertThat(MDC.get(RequestContext.REQUEST_ID_ATTRIBUTE)).isNull();
    }

    @Test
    void replacesUnsafeIncomingRequestId() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/");
        request.addHeader(RequestContext.REQUEST_ID_HEADER, "bad id with spaces");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> {
        });

        assertThat(response.getHeader(RequestContext.REQUEST_ID_HEADER))
                .matches("[a-f0-9-]{36}")
                .isNotEqualTo("bad id with spaces");
    }
    @Test void unknownHttpMethodCannotPlaceASecretInCompletionLogs()throws Exception {
        var logger=(ch.qos.logback.classic.Logger)org.slf4j.LoggerFactory.getLogger(RequestIdFilter.class);
        var appender=new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();appender.start();logger.addAppender(appender);
        try {
            var request=new MockHttpServletRequest("synthetic-private-method-token","/v1/songs");request.setQueryString("memo=synthetic-private-note");
            filter.doFilter(request,new MockHttpServletResponse(),(r,s)->{});
            assertThat(appender.list).extracting(ch.qos.logback.classic.spi.ILoggingEvent::getFormattedMessage).anyMatch(line->line.contains("method=OTHER")).allMatch(line->!line.contains("synthetic-private"));
        }finally{logger.detachAppender(appender);appender.stop();}
    }
}
