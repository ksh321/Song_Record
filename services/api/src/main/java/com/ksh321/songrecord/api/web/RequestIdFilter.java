package com.ksh321.songrecord.api.web;

import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RequestIdFilter.class);
    private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9._-]{8,64}");

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        String requestId = resolveRequestId(request.getHeader(RequestContext.REQUEST_ID_HEADER));
        long startedAt = System.nanoTime();

        request.setAttribute(RequestContext.REQUEST_ID_ATTRIBUTE, requestId);
        response.setHeader(RequestContext.REQUEST_ID_HEADER, requestId);
        // A syntactically valid client correlation header could itself contain a secret.
        // Preserve the public echo contract, but keep only its digest in server logs.
        MDC.put(RequestContext.REQUEST_ID_ATTRIBUTE, logCorrelation(requestId));

        try {
            filterChain.doFilter(request, response);
        } finally {
            long durationMillis = (System.nanoTime() - startedAt) / 1_000_000;
            log.info(
                    "request_completed method={} status={} duration_ms={}",
                    java.util.Set.of("GET","POST","PATCH","PUT","DELETE","HEAD","OPTIONS").contains(request.getMethod())?request.getMethod():"OTHER",
                    response.getStatus(),
                    durationMillis
            );
            MDC.remove(RequestContext.REQUEST_ID_ATTRIBUTE);
        }
    }

    private String resolveRequestId(String candidate) {
        if (candidate != null && SAFE_REQUEST_ID.matcher(candidate).matches()) {
            return candidate;
        }
        return UUID.randomUUID().toString();
    }
    static String logCorrelation(String value) {
        try{return "sha256:"+java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
        catch(java.security.NoSuchAlgorithmException error){throw new IllegalStateException("Log correlation unavailable");}
    }
}
