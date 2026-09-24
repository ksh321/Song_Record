package com.ksh321.songrecord.api.auth;

import java.util.Map;
import org.springframework.http.HttpStatus;
import com.ksh321.songrecord.api.web.ApiException;

final class ProofErrors {
    private ProofErrors() {}

    static ApiException invalid() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_INVALID_PROOF",
                "로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요.", false, Map.of());
    }

    static ApiException unavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "AUTH_PROVIDER_UNAVAILABLE",
                "로그인 제공자 확인이 지연되고 있습니다. 다시 시도해 주세요.", true, Map.of());
    }
}
