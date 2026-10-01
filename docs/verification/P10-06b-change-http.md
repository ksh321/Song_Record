# P10-06b — 증분 변경 수신: 인증된 HTTP 조회 계약

2026-10-01. 원본 P10-06 p00590~592, 설계 p00311~312/R040과 P07-05 변경 로그에 근거한 서버 HTTP 범위다. P10-06a의 일관 조회를 사용하며 앱의 로컬 커밋·커서 전진 연결은 아직 구현하지 않았다.

GET /v1/sync/changes?after_seq=<성공 적용한 순번>&limit=<1~100, 기본50>. 응답은 after_seq/next_seq/head_seq/has_more/changes이며 변경의 순번·엔터티·UUID·revision·UPSERT/DELETE·payload를 보존한다. UUID 표식/DELETE의 제품 의미를 이 계층에서 임의 재해석하지 않는다. 만료는409 CURSOR_EXPIRED, 잘못된 위치/중복/알 수 없는 query는400 INVALID_CURSOR다. CONDITION은 기존 AccountChanges 엔터티 코드이며 초기 사본의 RECORDING_CONDITION과 코드가 다른 점을 클라이언트 연결에서 명시적으로 매핑해야 한다.

ChangeQueries가 인증 후 입력을 검사하고 ChangeReadView로 계정 범위 조회를 수행한다. 응답 구성 뒤에도 세션을 재검증한다. ChangeHttpSecurityConfiguration은 해당 정확 GET만 인증 처리기로 전달하고 POST/DELETE/HEAD/하위 경로를 계속 거절한다. 세션 쿠키 생성 없음, 성공 응답 no-store. 외부 콘솔 권한/보호 규칙을 변경하지 않았다.

검증:
```text
gradlew.bat test --tests '*ChangeHttpTests' --tests '*ChangeReadViewTests' --tests '*ChangeWindowTests' --no-daemon
gradlew.bat test --tests '*ChangeHttpTests' --no-daemon
.local/contract-venv/Scripts/python.exe infra/scripts/verify_api_contract.py
```
첫 실행 HTTP5+기반14 PASS/MySQL7 skip. 최종 세션 폐기 사례 추가 후 HTTP **6 PASS**, 실패0. OpenAPI/로컬 참조/보안/기존 wire7개/경계 사례 **141 PASS**(이번 계약 사례7개 추가). 테스트 삭제·약화 없음. 상세 .local/workflow/p10-06b-http-test.log 및 p10-06b-http-final-test.log. 실제 MySQL은 선행a의 CI에서 별도 확인한다.

현재 모델 별도 검토: 인증 우선·최종 폐기 차단·정확 경로만 허용·장기 세션 미생성·엄격 정수/상한·새 커서의 의미를 실제 diff/테스트와 대조했다. 새 에이전트 위임 없음. 인증/동기화 위험도에 높은 추론이 적합하나 실행 모델/속도 설정 변경을 확인했다고 주장하지 않는다. 커밋 및 정확 SHA CI는 후속 기록/Git history로 식별한다. 이 서버 API 범위에는 사용자 폰 조작이 필요하지 않다.
