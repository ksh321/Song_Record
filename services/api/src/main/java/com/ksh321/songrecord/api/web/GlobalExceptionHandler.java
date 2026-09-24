package com.ksh321.songrecord.api.web;

import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ApiErrorResponse> handleApiException(
            ApiException exception,
            HttpServletRequest request
    ) {
        log.warn(
                "api_error code={} exception_type={}",
                exception.code(),
                exception.getClass().getSimpleName()
        );

        return ResponseEntity
                .status(exception.status())
                .body(error(
                        exception.code(),
                        exception.getMessage(),
                        exception.retryable(),
                        RequestContext.requestId(request),
                        exception.details()
                ));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ApiErrorResponse> handleValidation(
            MethodArgumentNotValidException exception,
            HttpServletRequest request
    ) {
        List<String> fields = exception.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(error -> error.getField())
                .distinct()
                .sorted()
                .toList();

        log.warn("api_error code=VALIDATION_FAILED invalid_field_count={}", fields.size());

        return ResponseEntity
                .badRequest()
                .body(error(
                        "VALIDATION_FAILED",
                        "요청 값이 올바르지 않습니다.",
                        false,
                        RequestContext.requestId(request),
                        Map.of("fields", fields)
                ));
    }

    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
    ResponseEntity<ApiErrorResponse> handleUnreadable(HttpServletRequest request) {
        // Never return/log the parser message: a malformed body can contain a credential.
        return ResponseEntity.badRequest().body(error("VALIDATION_FAILED",
                "요청 값이 올바르지 않습니다.", false, RequestContext.requestId(request), Map.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiErrorResponse> handleUnexpected(
            Exception exception,
            HttpServletRequest request
    ) {
        log.error("api_error code=INTERNAL_SERVER_ERROR exception_type={}",
                exception.getClass().getSimpleName());

        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(error(
                        "INTERNAL_SERVER_ERROR",
                        "서버에서 요청을 처리하지 못했습니다.",
                        true,
                        RequestContext.requestId(request),
                        Map.of()
                ));
    }

    private ApiErrorResponse error(
            String code,
            String message,
            boolean retryable,
            String requestId,
            Map<String, Object> details
    ) {
        return new ApiErrorResponse(new ApiErrorResponse.ApiError(
                code,
                message,
                retryable,
                requestId,
                details
        ));
    }
}
