package com.ksh321.songrecord.api.auth;

import java.io.IOException;

@FunctionalInterface
interface KakaoTokenInfoClient {
    Response retrieve(String accessToken) throws IOException, InterruptedException;

    record Response(int status, byte[] body) {
        @Override public String toString() { return "KakaoTokenInfoResponse[redacted]"; }
    }
}
