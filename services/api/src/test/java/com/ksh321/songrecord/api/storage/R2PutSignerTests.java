package com.ksh321.songrecord.api.storage;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class R2PutSignerTests {
    @Test void actualSdkSignsTemporaryPutOnlyForTenMinutesAndClipsAttemptLifetime(){
        var env=new R2StorageTests().environment("dev","api");
        try(var signer=new R2StorageConfiguration().r2PutSigner(env)){
            var key=new StorageObjectKeys.Temporary(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());
            var first=signer.sign(key,Instant.now().plusSeconds(86400));
            assertThat(first.url()).contains("/song-record-dev-temporary/"+key.value()).contains("X-Amz-Expires=600").doesNotContain("fixture-secret");
            assertThat(first.headers().keySet()).contains("host");assertThat(first.toString()).isEqualTo("SignedPut[REDACTED]");
            Instant deadline=Instant.now().plusSeconds(30);var last=signer.sign(key,deadline);
            assertThat(last.expiresAt()).isBeforeOrEqualTo(deadline);assertThat(last.url()).doesNotContain("X-Amz-Expires=600");
            assertThatThrownBy(()->signer.sign(key,Instant.now())).isInstanceOf(IllegalStateException.class);
        }
    }
}
