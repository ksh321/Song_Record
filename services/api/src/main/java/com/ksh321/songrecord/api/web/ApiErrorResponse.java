package com.ksh321.songrecord.api.web;

import java.util.Map;

public record ApiErrorResponse(ApiError error) {

    public record ApiError(
            String code,
            String message,
            boolean retryable,
            String request_id,
            Map<String, Object> details
    ) {
    }
}
