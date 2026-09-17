package com.ksh321.songrecord.api.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;

class ApiErrorResponseTests {

    @Test
    void keepsThePublicErrorContract() {
        ApiErrorResponse response = new ApiErrorResponse(new ApiErrorResponse.ApiError(
                "VALIDATION_FAILED",
                "요청 값이 올바르지 않습니다.",
                false,
                "request-123",
                Map.of("field", "title")
        ));

        assertThat(response.error().code()).isEqualTo("VALIDATION_FAILED");
        assertThat(response.error().retryable()).isFalse();
        assertThat(response.error().request_id()).isEqualTo("request-123");
        assertThat(response.error().details()).containsEntry("field", "title");
    }
}
