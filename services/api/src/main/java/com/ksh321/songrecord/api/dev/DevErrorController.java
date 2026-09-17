package com.ksh321.songrecord.api.dev;

import java.util.Map;

import com.ksh321.songrecord.api.web.ApiException;

import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Profile("dev")
public class DevErrorController {

    @GetMapping("/api/dev/errors/sample")
    void sampleValidationError() {
        throw new ApiException(
                HttpStatus.BAD_REQUEST,
                "VALIDATION_FAILED",
                "의도한 검증 오류입니다.",
                false,
                Map.of("field", "sample")
        );
    }
}
