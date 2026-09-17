package com.ksh321.songrecord.api.web;

import jakarta.servlet.http.HttpServletRequest;

public final class RequestContext {

    public static final String REQUEST_ID_ATTRIBUTE = "request_id";
    public static final String REQUEST_ID_HEADER = "X-Request-Id";

    private RequestContext() {
    }

    public static String requestId(HttpServletRequest request) {
        Object value = request.getAttribute(REQUEST_ID_ATTRIBUTE);
        return value instanceof String requestId ? requestId : "unknown";
    }
}
