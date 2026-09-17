package com.ksh321.songrecord.api.web;

import java.util.Map;

import com.fasterxml.jackson.annotation.JsonProperty;

public record ApiErrorResponse(ApiError error) {

    public record ApiError(
            String code,
            String message,
            boolean retryable,
            @JsonProperty("request_id") String requestId,
            Map<String, Object> details
    ) {
    }
}
