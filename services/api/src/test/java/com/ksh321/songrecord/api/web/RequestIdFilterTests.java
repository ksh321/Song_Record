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
    void keepsSafeIncomingRequestIdAndExposesItToLogsAndResponse() throws Exception {
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
        assertThat(mdcValue).hasValue("client-request-123");
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
}
