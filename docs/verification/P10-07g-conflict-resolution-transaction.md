# P10-07g — 충돌 해결의 계정 격리 보존 트랜잭션

2026-10-01. R038 / P10-07 원본3방향 충돌 처리. 현재 모델 직접 구현 후 코드 검토.

- AccountStore의 계정 직렬화와 SQLite 트랜잭션 안에서 원본 요청·시도·응답·로컬 입력을 대조한다. 이미 해결됐거나 보류/삭제/새 서버 기준/같은 revision 다른 근거이면 거절한다.
- 현재 선택으로 새 op_id의 PATCH와 초기 재시도 예산, 서버 기준, 명시 선택 이력, 업무 사본을 함께 저장한다. 원래 CONFLICT 요청·wire·시도/예산은 바꾸지 않는다. 서버 선택만이면 새 전송을 만들지 않는다.
- 새 로컬 편집이 있으면 해당 입력은 보존하며 원래 순서의 해결 요청만 앞서 전송된다. 후속 오래된 기준 요청을 임의로 최신 기준으로 고쳐 보내지 않는다.
- 저장 직전 계정 fence가 실패하면 새 요청·예산·이력·사본이 모두 롤백된다. 파일 삭제 경로 없음.
- 새 요청 ACK 때 유효한 해결 이력으로 보존된 원본만 미완료 입력 집계에서 제외한다. 다른 미전송/보류 입력이 있으면 기존 보존 동작을 유지한다. 원본을 ACKED로 위장하지 않는다.

## 실제 검증

- 최초 `flutter test --no-pub test/conflict_resolution_store_test.dart`: **7 PASS**.
- 관련 `metadata_dispatcher_test.dart canonical_song_store_test.dart mutation_retry_test.dart`: **85 PASS**. 함께 추가한 새 테스트는 지역 함수 선언 순서 때문에 로드 실패했고 함수 위치를 보정했다. 제품/기존 테스트 제약 변경 없음.
- 보완 후 `flutter test --no-pub test/conflict_resolution_store_test.dart`: **11 PASS**. 최종 계정 fence 전체 롤백, 합성 파일 바이트 보존, 최신/삭제/동일 revision 불일치, 오래된 로컬 입력, 중복/ID 충돌, 정상 전송1회/ACK 사본 반영, 최신 미전송 입력 보존을 확인했다.
- `dart analyze lib/core/database/account_store.dart lib/core/database/conflict_resolution_store.dart test/conflict_resolution_store_test.dart`: **No issues found**. `git diff --check` 통과.
- 로그 `.local/workflow/p10-07g-{test,regression,final}.log`. 커밋은 Git 이력, 필수 CI는 후속 기록.

전체 P10-07 완료 아님. 사용자 선택 화면/컨트롤러 연결과 새 기능 실기는 아직 수행하지 않았다. 해당 저장 API는 최신 계정/원본/로컬 입력 검증을 요구하며 UI가 과거 응답을 저장 권한으로 취급하면 안 된다. 모델/속도 변경 적용을 주장하지 않는다.
