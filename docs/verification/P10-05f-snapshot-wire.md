# P10-05f — 모바일 사본 응답·전체 해시 검증

2026-09-30. P10-05/D09의 엔터티 완결성·계정/사본 귀속·부분 수신 보호 기반. 현재 모델 직접 구현·별도 코드 검토 단계, 새 에이전트 없음.

## 구현

- `apps/mobile/lib/core/sync/snapshot_response.dart`: READY manifest의 19종 개수·기준 cursor·고정30분 TTL·해시·스키마 검사. 페이지의 같은 token/cursor/expiry/entity, 행 ordinal 연속성, user_id/리소스 키, 다음 cursor/총개수 관계를 검사한다. 객체를 외부 수정해도 저장 해시 원문은 바뀌지 않는다.
- SnapshotIntegrity는 entity/ordinal 순서로 원문을 스트리밍 SHA-256 검증한다. 누락·중복·순서 위반·내용 변조·검증 도중 만료를 거절한다. 검증 실패 객체를 계속 사용해 통과시키지 않는다. 실제 로컬 DB 덮어쓰기/커서 변경은 아직 연결하지 않았다.
- 서버 SnapshotQueries와 OpenAPI에 `canonical_payload` 추가. JSON 숫자를 Dart에서 재직렬화하면 Java BigDecimal의 지수/정밀도와 달라질 수 있어, 기존 manifest 계산에 사용한 정확한 문자열을 전달한다. 저장된 manifest 알고리즘/기존 사본을 바꾸지 않는다. payload 객체와 문자열의 JSON 의미가 다르면 거절한다. 원문을 UTF-8로 해시·staging 보관하며 UI에 노출하는 새 사용자 정책은 아니다.
- `fixtures/contracts/snapshot-wire.json`: 합성 계정/곡·한글/이모지·1E+2·1.23·19종 개수를 가진 공통 자료. 서버 실제 MySQL 저장/정규화/게시 결과와 모바일 검증이 같은 해시를 확인한다. 실제 계정/개인 데이터 없음.

## 실제 실행

```text
flutter test --no-pub test/snapshot_response_test.dart --reporter expanded
flutter analyze --no-pub lib/core/sync/snapshot_response.dart test/snapshot_response_test.dart
gradlew.bat test --tests '*MySqlSnapshotSourceRowsTests' --tests '*SnapshotHttpTests' --offline --no-daemon
.local/contract-venv/Scripts/python.exe infra/scripts/verify_api_contract.py
```

Flutter8 통과, 분석 No issues found. 서버15 통과(source12+HTTP3, 실패/오류/skip0), OpenAPI/wire7/경계134 통과. 최초 분석의 중괄호·빈 List 타입 지적2개를 수정했다. 처음 제한된 실행의 Dart telemetry 파일 권한 오류는 포맷 자체 이후 발생한 환경 오류이며 허용된 실행 환경에서 포맷/테스트를 마쳤다. 제품 해결 실패 횟수로 합산하지 않는다.

현재 모델 검토: D09·서버 publish의 버전 prefix/BE 길이/UUID bytes/UTF-8 canonicalpayload와 Dart 검증을 대조했다. 숫자 정밀도를 클라이언트 재직렬화에 맡기지 않았고, 값/계정/범위 검증과 최종 hash 검증을 모두 유지했다. 폰 조작이나 신규 API의 실제 기기 실행을 수행했다고 기록하지 않는다. 사용자 직접 할 일0건.

로그: .local/workflow/p10-05-mobile-wire-test.log, p10-05-wire-server-test.log. 현재 로컬 검증·검토 완료, 커밋/정확 SHA CI는 후속 기록. 다음은 로컬 v5 비파괴 migration·영속 staging/재개·기존 미전송/파일 보존 원자 적용. 전체 P10-05 미완료.

서버 API 계약 검사 목록 보완도 포함: ApiContractTests5 실제 통과. e의 CI 실패를 보완하기 위한 변경이며 다른 검사를 제거하지 않는다. 소스/HTTP15와 별도 실행한5를 혼동하지 않는다.
