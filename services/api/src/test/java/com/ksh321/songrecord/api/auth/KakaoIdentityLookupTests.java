package com.ksh321.songrecord.api.auth;

import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import com.ksh321.songrecord.api.web.ApiException;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class KakaoIdentityLookupTests {
    private final AuthIdentityRepository repository = mock(AuthIdentityRepository.class);
    private KakaoIdentityLookup lookup(int status, String body) {
        return new KakaoIdentityLookup(new KakaoProofVerifier(1586938,
                token -> new KakaoTokenInfoClient.Response(status, body.getBytes(StandardCharsets.UTF_8))), repository);
    }
    @Test void invalidProofNeverQueriesDatabase() {
        assertThatThrownBy(() -> lookup(401, "{}").verifyAndFind("token")).isInstanceOf(ApiException.class);
        verifyNoInteractions(repository);
    }
    @Test void wrongAppNeverQueriesDatabase() {
        assertThatThrownBy(() -> lookup(200, "{\"id\":123,\"app_id\":99,\"expires_in\":60}")
                .verifyAndFind("token")).isInstanceOf(ApiException.class);
        verifyNoInteractions(repository);
    }
    @Test void existingLinkUsesVerifiedProviderAndId() {
        var verified = new VerifiedProviderIdentity("KAKAO", "123");
        var identity = new AuthIdentity(UUID.randomUUID(), UUID.randomUUID(), "KAKAO", "123");
        when(repository.find(verified)).thenReturn(Optional.of(identity));
        var result = lookup(200, "{\"id\":123,\"app_id\":1586938,\"expires_in\":60,\"email\":\"ignored@example.com\"}")
                .verifyAndFind("token");
        assertThat(result.verified()).isEqualTo(verified);
        assertThat(result.existingIdentity()).contains(identity);
        verify(repository).find(verified);
        verifyNoMoreInteractions(repository);
    }
    @Test void missingLinkDoesNotRegisterAnAccount() {
        when(repository.find(any())).thenReturn(Optional.empty());
        var result = lookup(200, "{\"id\":456,\"app_id\":1586938,\"expires_in\":60}").verifyAndFind("token");
        assertThat(result.existingIdentity()).isEmpty();
        verify(repository).find(new VerifiedProviderIdentity("KAKAO", "456"));
        verifyNoMoreInteractions(repository);
    }
}
