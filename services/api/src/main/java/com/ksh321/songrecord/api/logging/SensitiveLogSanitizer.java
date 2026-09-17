package com.ksh321.songrecord.api.logging;

import java.util.regex.Pattern;

public final class SensitiveLogSanitizer {

    private static final String REDACTED = "[REDACTED]";
    private static final Pattern BEARER_TOKEN =
            Pattern.compile("(?i)(Bearer\\s+)[A-Za-z0-9._~+/=-]+");
    private static final Pattern SENSITIVE_KEY_VALUE = Pattern.compile(
            "(?i)([\"']?(?:access_?token|refresh_?token|token|password|memo|signed_?url)[\"']?\\s*[:=]\\s*[\"']?)([^\\s,\"'&}]+)"
    );
    private static final Pattern SIGNED_URL_PARAMETER = Pattern.compile(
            "(?i)((?:X-Amz-Signature|X-Amz-Credential|X-Amz-Security-Token|signature|sig)=)([^&\\s]+)"
    );

    private SensitiveLogSanitizer() {
    }

    public static String sanitize(String value) {
        if (value == null) {
            return null;
        }

        String sanitized = BEARER_TOKEN.matcher(value).replaceAll("$1" + REDACTED);
        sanitized = SENSITIVE_KEY_VALUE.matcher(sanitized).replaceAll("$1" + REDACTED);
        return SIGNED_URL_PARAMETER.matcher(sanitized).replaceAll("$1" + REDACTED);
    }
}
