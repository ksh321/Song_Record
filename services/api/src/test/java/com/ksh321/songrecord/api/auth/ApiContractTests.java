package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.domain.DomainTypes;
import com.ksh321.songrecord.api.web.ApiErrorResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

/** Checks the real Java wire DTOs and controller mappings against the shared contract. */
class ApiContractTests {
    static Map<String, Object> spec;
    static Map<String, Object> schemas;
    static final JsonMapper json = JsonMapper.builder().build();
    static JsonNode wire;

    @BeforeAll static void load() throws Exception {
        spec = new Yaml().load(Files.readString(Path.of("../../docs/contracts/openapi.yaml")));
        schemas = map(map(spec.get("components")).get("schemas"));
        wire = json.readTree(Files.readString(Path.of("../../fixtures/contracts/api-wire.json")));
    }
    @SuppressWarnings("unchecked")
    static Map<String, Object> map(Object value) { return (Map<String, Object>) value; }

    @Test void implementedPathsExactlyMatchControllers() {
        var actual = new TreeSet<String>();
        for (var type : List.of(SocialAuthController.class, IdentityLinkController.class, com.ksh321.songrecord.api.songs.SongController.class, com.ksh321.songrecord.api.recordings.RecordingController.class)) {
            var base = AnnotatedElementUtils.findMergedAnnotation(type, RequestMapping.class);
            for (var method : type.getDeclaredMethods()) {
                var mapping = AnnotatedElementUtils.findMergedAnnotation(method, RequestMapping.class);
                if (mapping == null) continue;
                String suffix = mapping.path().length == 0 ? "" : mapping.path()[0];
                actual.add(mapping.method()[0].name().toLowerCase(Locale.ROOT) + " " + base.path()[0] + suffix);
            }
        }
        var documented = new TreeSet<String>();
        map(spec.get("paths")).forEach((path, methods) -> map(methods).forEach((method, value) -> {
            if ("implemented".equals(map(value).get("x-implementation-status")))
                documented.add(method + " /v1" + path);
        }));
        assertThat(documented).isEqualTo(actual);
    }

    @Test void authRequiredPropertiesMatchActualRecordComponents() {
        var types = Map.of(
            "LoginRequest", SocialAuthController.LoginRequest.class,
            "RefreshRequest", SocialAuthController.RefreshRequest.class,
            "AuthSession", SocialAuthController.LoginResponse.class,
            "Principal", SessionService.Principal.class,
            "LinkBegin", IdentityLinkController.Begin.class,
            "LinkProof", IdentityLinkController.Proof.class,
            "LinkChallenge", IdentityLinkService.Challenge.class,
            "Identity", IdentityLinkService.Identity.class,
            "ApiError", ApiErrorResponse.ApiError.class
        );
        types.forEach((name, type) -> {
            var actual = Arrays.stream(type.getRecordComponents()).map(c -> c.getName()).toList();
            var schema = map(schemas.get(name));
            assertThat(map(schema.get("properties")).keySet()).containsExactlyInAnyOrderElementsOf(actual);
            assertThat(new HashSet<>((List<?>) schema.get("required"))).isEqualTo(new HashSet<>(actual));
        });
    }

    @Test void realJavaSerializationMatchesSharedDartSessionAndChallengeExamples() {
        var session = wire.get("authSession");
        var dto = new SocialAuthController.LoginResponse(session.get("userId").asText(),
            session.get("deviceId").asText(), session.get("accessToken").asText(),
            session.get("refreshToken").asText(), session.get("accessExpiresAt").asText(),
            session.get("refreshExpiresAt").asText());
        assertThat(json.readTree(json.writeValueAsString(dto))).isEqualTo(session);
        var challenge = wire.get("linkChallenge");
        assertThat(json.readTree(json.writeValueAsString(new IdentityLinkService.Challenge(
            challenge.get("challengeId").asText(), challenge.get("nonce").asText(),
            challenge.get("expiresAt").asText())))).isEqualTo(challenge);
        var request = json.readValue(wire.get("loginRequest").toString(), SocialAuthController.LoginRequest.class);
        assertThat(json.readTree(json.writeValueAsString(request))).isEqualTo(wire.get("loginRequest"));
        var refresh = json.readValue(wire.get("refreshRequest").toString(), SocialAuthController.RefreshRequest.class);
        assertThat(json.readTree(json.writeValueAsString(refresh))).isEqualTo(wire.get("refreshRequest"));
    }

    @Test void errorEnvelopePreservesItsRealWireNames() {
        var error = new ApiErrorResponse(new ApiErrorResponse.ApiError("REVISION_CONFLICT",
            "최신 값을 확인해 주세요.", false, "contract-test-001",
            Map.of("current_revision", 2, "current", Map.of())));
        assertThat(json.readTree(json.writeValueAsString(error))).isEqualTo(wire.get("error"));
    }

    @Test void domainEnumsMatchSharedContractWithoutCaseConversionGuessing() {
        for (var type : List.of(DomainTypes.VersionCode.class, DomainTypes.KeyMode.class,
                DomainTypes.SongTier.class, DomainTypes.RecordingTier.class,
                DomainTypes.MetadataState.class, DomainTypes.CloudState.class,
                DomainTypes.BlockedReason.class, DomainTypes.LifecycleState.class)) {
            var names = Arrays.stream(type.getEnumConstants()).map(Enum::name).toList();
            assertThat(map(schemas.get(type.getSimpleName())).get("enum")).isEqualTo(names);
            assertThat(json.readTree(json.writeValueAsString(names))).isEqualTo(wire.get("enums").get(type.getSimpleName()));
        }
    }
}
