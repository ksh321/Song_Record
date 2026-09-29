package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.util.MultiValueMap;

/** D06 read-only catalog. Legacy definitions stay in storage, never in the selection catalog. */
public final class ConditionService {
    private final AccountAccess access;
    public ConditionService(AccountAccess access) { this.access = access; }
    public record Catalog(List<ConditionCatalog.Item> items) {}
    public Catalog list(String auth, String device, MultiValueMap<String,String> params) {
        access.authenticate(auth, device);
        if (!params.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED",
            "고정 카탈로그는 조회 조건을 받지 않습니다.", false, Map.of());
        return new Catalog(ConditionCatalog.ITEMS);
    }
    public IdempotentMutations.Reply create(String auth,String device,String op,String body) { return readOnly(auth,device); }
    public IdempotentMutations.Reply rename(String auth,String device,String op,String id,String body) { return readOnly(auth,device); }
    public IdempotentMutations.Reply archive(String auth,String device,String op,String id,String body) { return readOnly(auth,device); }
    private IdempotentMutations.Reply readOnly(String auth,String device) {
        access.authenticate(auth,device);
        throw new ApiException(HttpStatus.METHOD_NOT_ALLOWED,"CONDITION_CATALOG_READ_ONLY",
            "컨디션 카탈로그는 변경할 수 없습니다.",false,Map.of());
    }
}
