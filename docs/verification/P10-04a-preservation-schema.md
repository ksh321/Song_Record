# P10-04a — canonical 매핑의 보존 저장 기반

계획 검색본 p00584~p00586, 설계 p00293의 기존 요청·녹음 UUID/파일·개인 편집 보존 요구를 위한 부가 저장 구조다. P10-03b 폰 실기와 독립적으로 별도 worktree에서 구현했다. 실제 사용자 DB를 열거나 이관하지 않았다.

## 변경

- `local_schema.drift`: alias/대체 요청 이력/선택 편집/송신 보류의 4개 테이블. 불변 증거·일회 해제·대체 순서·순환 차단. WITHOUT ROWID와 중복 키 삽입 차단으로 REPLACE 우회를 막는다.
- `account_database.dart`: v1/2/3→4 명시 이관. v3 자동 예산과 예약 시각을 재초기화하지 않는다. 기존 v1~v3 스냅샷 보존.
- `account_store.dart`: 복구 내보내기에 새 4개 테이블 포함. 실제 canonical 응답 반영·참조 재작성·대체 큐 실행은 P10-04b 후속이다.
- `canonical_schema_test.dart`: 합성 DB/파일로 기존 모든 행·wire·예산·cursor·journal·파일 바이트 비교, 제약 거부, populated 4테이블 내보내기 비교.

## 실행 증거

별도 브랜치 `codex/p10-04-storage`, 기준 9105beeb16e4f374348dd5adefcbfe2feb559450.

- `dart run build_runner build`: 성공. `dart run drift_dev make-migrations --no-test`: v4 생성 성공. 수정 중 신규 스냅샷 충돌은 미배포 v4를 로컬 폴더에 보관한 뒤 재생성했다. 사용자 DB/기존 v1~v3 삭제 아님.
- `flutter test --no-pub test/canonical_schema_test.dart test/account_store_test.dart test/mutation_retry_test.dart --reporter expanded`: 44 통과·Windows symlink 권한 1 skipped.
- `flutter analyze --no-pub`: import 정렬 보완 후 No issues found.
- Worker Astra/high: DB·불변 요청 변경 위험. Reviewer Astra/high가 REPLACE/역순 대체 체인 P2 제시, 보완 후 Astra/xhigh가 숨은 rowid 우회 P2 제시. 3차 Astra/xhigh 검수에서 기존 local_mutations.rowid 변경으로 순서를 바꾸는 경로를 추가 발견했다. 실패 누적 3/최대 단계 0으로 Astra/ultra 작업자에 상향해 보완 중. 반복 명령이나 환경 오류는 논리 실패에 가산하지 않았다.
- Standard/default·Fast 끔 요청, CLI 모델/추론 확인. 실제 서버 속도 telemetry 미노출로 미확인.

상세 로그 `.local/workflow/p10-04-v4-rowid-test.log`. 별도 검수·main 통합·대상 커밋 필수 CI 전 완료로 판정하지 않는다. 폰 실기를 실행했다고 기록하지 않는다.

## 후속

P10-04b: 검증된 200/created=false canonical 응답의 원자 적용, 참조와 대체 큐/보류 연결, 늦은 응답·계정 격리·재시작·복구 순서 검증. 저장 기반만으로 전체 P10-04 완료 아님.

## 최대 추론 보완

Astra/ultra 작업자 제안으로 v4에 기존 요청 rowid UPDATE 불변 트리거를 추가했다. master는 재삽입/숨은 rowid 충돌·비양수 새 순서·삭제도 거부하도록 추가했다. 기존 행을 수정하지 않는다. 관련 44 통과/1 skip·분석 통과 후 별도 ultra 검수에서 확정 제품 결함 없음, INSERT 분기 회귀 누락 P2를 받았다. 실패 누적 4/최대 단계 1 유지. 새로운 op_id의 rowid 충돌, 명시적 0/-1/-2 삽입, v3의 기존 -1행 보존, 생략 rowid 정상 삽입 회귀를 추가해 새 테스트 파일 5개 통과했다. 두 번째 ultra 검수 진행 중.

최종 별도 Astra/ultra 검수에서 위 INSERT 분기 누락 해소·추가 차단 없음 확인. 독립 브랜치 5da5226을 main에 정상 cherry-pick하여 대상 5c23040abf78e34ea537016545ab78244764a79d로 통합했다. 현재 main에서 canonical_schema/account_store/mutation_retry/sync_controller 4파일을 함께 실행해 **84 통과·Windows symlink 1 skipped**, 분석 No issues found. 지연 401/403의 4회귀도 이 통합 범위에 포함된다. 일반 push 완료, 대상 SHA 필수 CI 대기.

대상 5c23040abf78e34ea537016545ab78244764a79d 필수 CI 4개·필수 job 모두 success: [CI 36571851767](https://github.com/ksh321/Song_Record/actions/runs/36571851767), API contract 36571851768, Idempotency MySQL 36571851857, Development workflow 36571851901. **P10-04a 저장 기반 완료**, P10-04 전체 매핑 완료 아님.
