package com.ksh321.songrecord.api.idempotency;

import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.*;
import org.springframework.http.HttpStatus;
import tools.jackson.core.StreamReadFeature;
import tools.jackson.databind.*;
import tools.jackson.databind.json.JsonMapper;

/** Application canonicalization, not RFC 8785. No trimming strings or sorting arrays. */
public final class CanonicalRequest {
    private static final JsonMapper JSON = JsonMapper.builder()
            .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)
            .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
            .enable(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS).build();
    private CanonicalRequest() {}

    public static String hash(String method, String target, String body) {
        if (!Set.of("POST", "PUT", "PATCH", "DELETE").contains(method == null ? "" : method)
                || target == null || !target.startsWith("/v1/") || target.length() > 2048
                || target.indexOf('?') >= 0 || target.indexOf('#') >= 0
                || target.chars().anyMatch(Character::isISOControl)) throw invalid();
        // Target is supplied by the route adapter, including concrete resource IDs.
        String input = method + "\n" + target + "\n" + canonical(body);
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(input.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) { throw new IllegalStateException("SHA-256 unavailable"); }
    }

    public static String canonical(String text) {
        if (text == null || text.length() > 1_048_576) throw invalid();
        try {
            var root = JSON.readTree(text);
            if (root == null || root.isMissingNode()) throw invalid();
            var result = new StringBuilder();
            append(root, result, 0);
            return result.toString();
        } catch (ApiException e) { throw e; }
        catch (RuntimeException e) { throw invalid(); }
    }
    private static void append(JsonNode node, StringBuilder out, int depth) {
        if (depth > 64) throw invalid();
        if (node.isObject()) {
            var names = new TreeSet<String>();
            node.properties().forEach(entry -> names.add(entry.getKey()));
            out.append('{'); boolean first = true;
            for (var name : names) {
                if (!first) out.append(','); first = false;
                out.append(JSON.writeValueAsString(name)).append(':');
                append(node.get(name), out, depth + 1);
            }
            out.append('}');
        } else if (node.isArray()) {
            out.append('['); boolean first = true;
            for (var value : node) {
                if (!first) out.append(','); first = false;
                append(value, out, depth + 1);
            }
            out.append(']');
        } else if (node.isNumber()) {
            out.append(node.decimalValue().stripTrailingZeros().toString());
        } else out.append(JSON.writeValueAsString(node));
    }
    static ApiException invalid() {
        return new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED",
                "요청 값이 올바르지 않습니다.", false, Map.of());
    }
}
