package com.ksh321.songrecord.api.web;

import java.util.Map;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final boolean retryable;
    private final Map<String, Object> details;

    public ApiException(
            HttpStatus status,
            String code,
            String message,
            boolean retryable,
            Map<String, Object> details
    ) {
        super(message);
        this.status = status;
        this.code = code;
        this.retryable = retryable;
        this.details = details == null ? Map.of() : Map.copyOf(details);
    }

    public HttpStatus status() {
        return status;
    }

    public String code() {
        return code;
    }

    public boolean retryable() {
        return retryable;
    }

    public Map<String, Object> details() {
        return details;
    }
}
