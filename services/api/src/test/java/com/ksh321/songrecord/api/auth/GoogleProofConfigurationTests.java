package com.ksh321.songrecord.api.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;

class GoogleProofConfigurationTests {
    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(GoogleProofConfiguration.class);

    @Test
    void disabledByDefault() {
        runner.run(context -> assertThat(context).doesNotHaveBean(GoogleProofVerifier.class));
    }

    @Test
    void enabledWithoutAudienceFailsStartup() {
        runner.withPropertyValues("auth.google.enabled=true")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void configuredVerifierStartsWithoutCallingGoogle() {
        runner.withPropertyValues("auth.google.enabled=true",
                        "auth.google.server-client-id=server.apps.googleusercontent.com")
                .run(context -> assertThat(context).hasSingleBean(GoogleProofVerifier.class));
    }
}
