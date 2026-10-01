# P10-07e — 충돌 해결 후 전송 순서 보존

2026-10-01. 원본 P10-07 3방향 충돌 처리의 큐 읽기 연결. P10-07d의 v6 해결 이력을 사용하며 실제 해결 저장/UI는 후속 작업이다.

- mapping eligibility가 해결 이력의 계정·409 REVISION_CONFLICT·시도 횟수·서버 기준·대상·새 요청과 최초 논리 순서를 재확인한다.
- 해결된 원본은 CONFLICT 및 모든 요청 필드를 그대로 보관하고 전송 후보에서만 제외한다. 새 요청이 물리적으로 뒤에 추가되어도 최초 순서를 계승한다. 반복 충돌에서도 나중 편집이 앞서 전송되지 않는다.
- 새 요청이 없는 명시 서버 선택도 별도 이력으로 인정한다. 기존 mapping hold나 근거 불일치는 같은 논리 대상의 후속 전송도 막는다. JSON 자체를 읽을 수 없으면 예외로 전송을 중단한다.
- 현재 모델 코드 검토: 원본 UPDATE 없음, 새 요청 상태/시도 횟수는 이후 정상 전송에 따라 바뀔 수 있으므로 읽기 시 PENDING/0으로 고정하지 않음, 실제 전송 정책은 기존 planner/retry가 계속 적용함. 서버 성공으로 위장하지 않음.

## 실제 검증

- `flutter test --no-pub test/conflict_resolution_schema_test.dart test/dependency_planner_test.dart test/canonical_song_store_test.dart test/mutation_retry_test.dart`: 첫 실행 85 PASS/1 FAIL. 새 테스트가 DB에 없는 BLOCKED 상태를 사용하여 DB CHECK에서 거절됨. 기존 테스트나 제품 제약을 약화하지 않고 허용된 FAILED 상태로 시험 데이터를 수정했다.
- `flutter test --no-pub test/conflict_resolution_schema_test.dart`: 수정 후 **12 PASS**. 기존 관련 테스트 74건은 첫 실행 통과했다.
- `dart analyze lib/core/database/conflict_eligibility.dart lib/core/database/mapping_eligibility.dart test/conflict_resolution_schema_test.dart`: 중괄호 스타일 정보 1건 보완 후 **No issues found**.
- `git diff --check`: 통과. 상세 로그 `.local/workflow/p10-07e-test.log`, `p10-07e-recheck.log`.
- 검증 범위: 원본 보존/대체 전송, 반복 충돌의 논리 순서, 서버만 선택, 근거 변경 격리, 기존 mapping 보류 유지. 새 폰 실기 수행으로 기록하지 않는다.

커밋은 이 문서 Git 이력으로 식별한다. 필수 CI와 실제 해결 트랜잭션/UI는 후속이며 전체 P10-07 완료가 아니다. 모델·속도 변경은 실제 확인되지 않아 주장하지 않는다.
