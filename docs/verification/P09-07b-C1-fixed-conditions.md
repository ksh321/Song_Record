# P09-07b-C1 — 승인된 D06 고정 컨디션 보정

- 요구사항: D06, R029·R030 / 후속 보정 ID P09-07b-C1. 원본 사용자 정의 컨디션 요구는 D06 승인 범위에서만 대체한다.
- 시작 SHA: `27c5a4f80f2e1e177eb9db888f5b64d7f7ed8209`. 당시 작업 트리 clean, origin/main 일치. P09-07b-C1/P10-02b 미구현 확인.
- 현재 상태: 구현·관련 자동 검증 수행, 검수 지적 보완 MySQL 1 통과, 코드 검수 지적 해결·새 결함 없음, 테스트 원본 XML 보충 확인 완료. 커밋/필수 CI 전이므로 완료 아님.

## 변경과 보존

GET /conditions는 VERY_GOOD/GOOD/NORMAL/BAD의 코드·고정 이름·순서·catalog_version=1을 반환한다.
인증된 POST/PATCH/archive는 본문 없이도 405 CONDITION_CATALOG_READ_ONLY이며 멱등 영수증을 쓰지 않는다.
POST 초안 및 일반 PATCH condition_code는 고정 enum/null만 허용한다. PATCH 누락은 기존 값을 유지한다.
기존 UUID 조건은 조회/필터에서 읽을 수 있고 새 선택에서는 거절한다. 사용자 태그 동작은 유지한다.

V16은 기존 V1~V15를 수정하지 않는다. 기존 조건 정의·이름·archive·녹음 관계·스냅샷을 일괄 변경/삭제하지 않는다.
새 recording_condition_history에 기존 조건을 복사하고 교체/해제 시 과거 값도 트랜잭션으로 보존한다.
이력의 직접 UPDATE/DELETE는 DB에서 거절한다. 녹음 영구 삭제에 따른 관계 정리는 기존 소유 녹음의 수명에 따른다.
현재 스냅샷은 같은 코드 수정 때 유지하며 새 선택만 불변 카탈로그 이름을 쓴다.
이력/메타정보/변경 로그/멱등 영수증 실패는 함께 롤백한다.

핵심 코드:
- services/api/.../classifications/ConditionCatalog.java, ConditionService.java, ConditionController.java
- services/api/.../recordings/RecordingDrafts.java, RecordingEditing.java
- services/api/src/main/resources/db/migration/V16__fixed_condition_catalog_and_history.sql
- docs/contracts/openapi.yaml / fixtures/contracts/api-schema-cases.json

## 실제 검증 및 실패 기록

기존 ENV-GRADLE-LOOPBACK Windows 실패 3회는 유지하고 재시도하지 않았다.
대신 별도 Linux Gradle 컨테이너와 tmpfs MySQL 8.4.11을 사용했다. 기존 개발 DB/볼륨은 연결하지 않았다.
Gradle 이미지: `gradle@sha256:1e11e6b7d3424da72d8f105e25e7fa6173cf42240aa6c06e1660f8629abc4401`.
테스트 소스는 읽기 전용 마운트에서 컨테이너 작업 폴더로 복사하고 결과 XML만 .local로 회수했다.

| 실행 명령(컨테이너 내부/저장소 루트) | 실제 결과 |
|---|---|
| `gradle test --no-daemon --tests "*ConditionTests" --tests "*RecordingEditingTests" --tests "*RecordingDraftTests"` | 16 통과, 실패/skip 0 |
| 위 초안 입력 추가 후 ConditionTests/RecordingDraftTests/ApiContractTests 및 MySQL conditions upgrade 메서드 실행 | 18 중 HEAD 응답 본문 검사 1 실패, 나머지 17 통과. MySQL V15→V16 보존 성공 |
| HEAD 명시적 무본문 처리 후 `gradle test --no-daemon --tests "*ConditionTests" --tests "*ApiContractTests"` | 10 통과, 실패/skip 0 |
| `.local/contract-venv/Scripts/python.exe infra/scripts/verify_api_contract.py` | OpenAPI/로컬 참조/보안/7 wire/125 경계 사례 통과 |
| 이력 UPDATE 거절 추가 후 `gradle test --no-daemon --tests "*MySqlIdempotencyTests.mysqlConditionsPreserveV15DataAndEnforceD06AfterUpgrade"` | 1 통과, 실패/skip 0, 종료 0 |
| 직접 DELETE 차단·PURGED 메타정보의 이력 보존·소유 녹음 물리 정리 추가 후 같은 MySQL 메서드 | 1 통과, 실패/skip 0, 종료 0 |
| `git diff --check` | 통과 |

계약 편집 중 YAML 들여쓰기 1회 및 응답 참조 1회 실패를 수정했다. 이후 검증 통과.
별도 포맷 최소화 실험은 메모리 검증에서 실패해 파일에 적용하지 않았다. 승인된 의미를 바꾸지 않았다.
C1-HEAD 문제는 1회 실패 후 구현 수정으로 해결. C1-PURGE-FIXTURE는 deleted_at 누락으로 1회 실패 후 기존 제약을 유지하며 fixture를 수정해 통과. 기존 기능의 실기 재요청은 하지 않았다.
새 변경은 서버 계약/DB 범위이며 앱 UI·오디오·권한을 변경하지 않아 이번 단계에서 폰 조작 검증은 선정하지 않았다.

## 별도 에이전트

작업자 Astra/high: D06·DB 보존 위험 때문에 선택. 분석/패치 제안을 마스터가 실제 파일에 적용.
검수자 Astra/high: 원본 D06·실제 전체 diff·신규 V16·관측 결과를 대조. 이력 UPDATE 방어 누락 지적.
마스터가 이를 중요 데이터 보존 지적으로 판단해 보완하고 Astra/xhigh 재검수에서 직접 DELETE 방어도 보완. 실제 XML과 변경 부분을 전달해 최종 검수한다.
모든 CLI 요청 default(Standard)/Fast=false, 실제 모델·추론은 CLI 헤더 관측. 서버 실행 tier는 미노출로 미확인.
로컬 상세 자료는 .local/workflow/에 두고 알림 topic·인증·개인 데이터는 이 기록에 넣지 않는다.

## 다음

이력 보완 MySQL 검증 → 독립 재검수 → 일반 커밋/푸시 → 정확한 SHA의 기존 필수 CI 4개 → 진행 기록.
최종 MySQL XML은 `mysqlConditionsPreserveV15DataAndEnforceD06AfterUpgrade()` 1개, failures/errors/skipped 모두 0이다. PowerShell XML→JSON 전달 시 testcase가 빈 배열로 표시되어 원본 XML 행을 별도로 보충했다.

그 후 P10-02b의 실제 HTTP 송신/원자적 ACK 반영. 사전 작업자 분석은 C1 코드와 독립적으로 진행한다.
P06는 사용자 확인으로 기존 검증 완료이며 Windows Gradle/개발 DB 준비는 별도 환경 문제다.
