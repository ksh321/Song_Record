package com.ksh321.songrecord.api.logging;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class SensitiveLogSanitizerTests {

    @Test
    void masksTokensPasswordsMemosAndSignedUrlCredentials() {
        String source = """
                Authorization=Bearer secret-token
                {"access_token":"access-secret","refresh_token":"refresh-secret","password":"pw-secret","memo":"private-note"}
                https://example.test/audio?X-Amz-Credential=credential-secret&X-Amz-Signature=signature-secret
                """;

        String sanitized = SensitiveLogSanitizer.sanitize(source);

        assertThat(sanitized)
                .contains("[REDACTED]")
                .doesNotContain(
                        "secret-token",
                        "access-secret",
                        "refresh-secret",
                        "pw-secret",
                        "private-note",
                        "credential-secret",
                        "signature-secret"
                );
    }

    @Test
    void acceptsNull() {
        assertThat(SensitiveLogSanitizer.sanitize(null)).isNull();
    }
}
