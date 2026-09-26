package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;

/** Request-scoped authority derived exclusively from a live server session. */
public final class AccountAccess {
    private final SessionService sessions;
    public AccountAccess(SessionService sessions) { this.sessions = sessions; }

    public Account authenticate(String authorization, String device) {
        if (authorization == null || !authorization.startsWith("Bearer ")) throw unauthorized();
        UUID deviceId;
        try {
            deviceId = UUID.fromString(device);
            if (!deviceId.toString().equals(device)) throw unauthorized();
        } catch (IllegalArgumentException | NullPointerException e) { throw unauthorized(); }
        String token = authorization.substring(7);
        return new Account(token, sessions.authenticate(token, deviceId));
    }

    public SessionService.Principal revalidate(Account account) {
        if (account == null) throw unauthorized();
        var current = sessions.authenticate(account.token, account.principal.deviceId());
        if (!account.principal.equals(current)) throw unauthorized();
        return current;
    }

    private static ApiException unauthorized() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_INVALID_SESSION",
                "다시 로그인해 주세요.", false, Map.of());
    }

    public static final class Account {
        private final String token;
        private final SessionService.Principal principal;
        private Account(String token, SessionService.Principal principal) {
            this.token = token; this.principal = principal;
        }
        public SessionService.Principal principal() { return principal; }
        @Override public String toString() { return "Account[REDACTED]"; }
    }
}
