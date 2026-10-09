package com.ksh321.songrecord.api.storage;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class R2GetSignerTests {
    @Test void actualSdkSignsOwnedFinalGetForExactlyFiveMinutesWithoutNetwork() {
        var env=new R2StorageTests().environment("dev","api"); // Synthetic fixture credentials only.
        try(var signer=new R2StorageConfiguration().r2GetSigner(env)) {
            var key=new StorageObjectKeys.Final(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());
            var before=Instant.now();var result=signer.sign(key);
            assertThat(result.url()).contains("/song-record-dev-final/"+key.value())
                .contains("X-Amz-Expires=300").doesNotContain("fixture-secret");
            assertThat(result.expiresAt()).isBetween(before.plusSeconds(299),Instant.now().plusSeconds(301));
            assertThat(result.toString()).isEqualTo("SignedGet[REDACTED]");
        }
    }
}
