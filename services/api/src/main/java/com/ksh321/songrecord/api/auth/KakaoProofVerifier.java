package com.ksh321.songrecord.api.auth;

import java.io.IOException;
import tools.jackson.core.JacksonException;
import tools.jackson.core.StreamReadFeature;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Kakao SDK access tokens, verified online; never accepts a client-supplied user ID. */
public final class KakaoProofVerifier {
    private final long appId;
    private final KakaoTokenInfoClient client;
    private final JsonMapper json = JsonMapper.builder()
            .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).build();

    KakaoProofVerifier(long appId, KakaoTokenInfoClient client) {
        if (appId <= 0) throw new IllegalArgumentException("Kakao app ID must be positive");
        this.appId = appId;
        this.client = client;
    }

    public VerifiedProviderIdentity verify(String accessToken) {
        // Opaque bearer token, not a JWT payload. Reject whitespace/control/header injection.
        if (accessToken == null || accessToken.isEmpty() || accessToken.length() > 4096
                || !accessToken.matches("[A-Za-z0-9._~+/=-]+")) {
            throw ProofErrors.invalid();
        }
        KakaoTokenInfoClient.Response response;
        try {
            response = client.retrieve(accessToken);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw ProofErrors.unavailable();
        } catch (IOException exception) {
            throw ProofErrors.unavailable();
        }
        if (response.status() == 401) throw ProofErrors.invalid();
        if (response.status() != 200 && response.status() != 400) throw ProofErrors.unavailable();
        JsonNode body;
        try {
            if (response.body() == null || response.body().length > KakaoHttpTokenInfoClient.MAX_RESPONSE_BYTES) {
                throw ProofErrors.unavailable();
            }
            body = json.readTree(response.body());
        } catch (JacksonException exception) {
            throw ProofErrors.unavailable();
        }
        if (body == null || !body.isObject()) throw ProofErrors.unavailable();
        if (response.status() == 400) {
            JsonNode code = body.get("code");
            if (code != null && code.isIntegralNumber() && code.canConvertToInt()
                    && (code.intValue() == -401 || code.intValue() == -2)) throw ProofErrors.invalid();
            // Kakao -1 is a temporary platform failure, even though HTTP status is 400.
            throw ProofErrors.unavailable();
        }
        long id = integral(body, "id");
        long issuedAppId = integral(body, "app_id");
        long expiresIn = integral(body, "expires_in");
        if (id <= 0 || issuedAppId <= 0) throw ProofErrors.unavailable();
        if (issuedAppId != appId || expiresIn <= 0) throw ProofErrors.invalid();
        return new VerifiedProviderIdentity("KAKAO", Long.toString(id));
    }

    private static long integral(JsonNode body, String name) {
        JsonNode value = body.get(name);
        if (value == null || !value.isIntegralNumber() || !value.canConvertToLong()) {
            throw ProofErrors.unavailable();
        }
        return value.longValue();
    }
}
