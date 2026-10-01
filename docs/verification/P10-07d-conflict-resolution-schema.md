# P10-07d — 충돌 해결 이력 보존 스키마 v6

2026-10-01. 원본 P10-07 3방향 충돌 처리의 보존 저장 기반. P10-07a~c 비교 후 해결 결과를 기존 실패 요청과 분리해 보관하기 위한 추가 이관이다. 앱 해결 버튼/자동 재전송은 아직 연결하지 않는다.

## 변경과 현재 모델 코드 검토

- mutation_conflict_resolutions에 원래 op_id/시도 횟수, 서버 snapshot/revision, 명시 선택(LOCAL/SERVER), 새 요청 op_id(또는 요청 불필요), 최초 논리 순서와 시각을 저장한다.
- 현재 계정의 PATCH/REVISION_CONFLICT/409 근거만 허용한다. 새 요청은 같은 엔티티/대상·새 op_id·새 기준·미전송 상태이며 원래 행보다 뒤에 있어야 한다. 같은 요청을 성공 ACKED로 위장하거나 원본 payload를 고치지 않는다.
- 해결 이력의 UPDATE/DELETE/REPLACE와 해결된 원래 요청의 재시도 증가를 DB에서 거절한다. 반복 충돌의 새 해결도 최초 논리 순서를 계승한다. canonical mapping 보류 이력은 이 경로로 무시하지 않는다.
- v1~v5를 보존하며 v6 테이블/트리거만 추가한다. v5의 기존 사본 테이블을 다시 만들지 않는다. 복구 내보내기에 새 표를 포함했다. 예전 v1~v5 schema JSON은 수정하지 않았다.
- 스키마는 근거 보존 경계다. 도메인 비교/사용자 선택 일치/최신 계정 상태와 큐 연결은 후속 트랜잭션에서 재검증해야 한다. 테이블 존재만으로 충돌 해결이나 전체 P10-07 완료라고 판단하지 않는다.

## 실제 검증

- `dart run build_runner build`, `dart run drift_dev make-migrations --no-test`: 성공. json_each 열 이름 경고를 명시 별칭으로 보완했다.
- 동일 생성 명령 재실행 후 생성2파일+스키마6파일 SHA256 대조: **8개 모두 동일**.
- `flutter test --no-pub test/conflict_resolution_schema_test.dart test/canonical_schema_test.dart test/account_store_test.dart test/snapshot_schema_test.dart`: **50 PASS / 기존 Windows 심볼릭 링크 권한 검사1 SKIP**. SKIP을 통과로 계산하지 않는다. 해당 검사는 Linux CI 대상이다.
- v5의 비어 있지 않은 snapshot/행/진행/기준 포인터를 추가한 뒤 `flutter test --no-pub test/canonical_schema_test.dart --plain-name 'v5 to v6'`: **1 PASS**. 이전 큐·wire·재시도 예산·커서·합성 파일·기존 모든 테이블 값을 그대로 대조했다.
- 변경 직접 작성 Dart5파일 및 보완 이관 테스트 분석: **No issues found**.
- 새 스키마7개 테스트: 원본 모든 열/순서 보존, 요청 없는 서버 선택, 수정/삭제/교체/원래 요청 재시도 차단, 잘못된 계정·시도·revision/JSON·선택·순서·대상·이미 전송된 대체 요청 거절, 반복 충돌 순서 계승.
- 초기 실행의 기존 테스트2건은 미래 버전 오류 문자열(99→5에서99→6)과 데이터가 없는 새 표에 INSERT SELECT 0행을 실행한 기대 때문에 실패했다. 버전 기대를 수정하고, canonical 표의 기존 불변 검사와 실제 해결 행을 넣는 새 불변 검사를 분리했다. 검사 삭제/CI 비활성화 없음.

로그: .local/workflow/p10-07d-{generate,schema,final,v5,regenerate,remigration}.log. 현재 모델이 실제 SQL·생성 코드·이관 diff·검증 결과를 대조했다. DB 변경이므로 높은 추론이 필요한 범위이나 실제 모델/속도 변경을 주장하지 않는다. 실기 DB/앱에 v6를 설치하지 않았다. 커밋은 이 파일의 Git 이력, 필수 CI는 후속 통합 기록을 따른다.
