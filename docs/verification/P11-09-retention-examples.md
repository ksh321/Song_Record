# P11-09 선정 예제 검증

## 범위와 원본
- 사용자 승인: P11-09까지 원수 방식. Astra/medium 현재 대화 직접 구현·검사·별도 코드 검토. 하위 에이전트·추가 실행기 AI 호출 없음.
- 계획서 v1.0 p00634~636; 설계서 v1.11 6.1~6.3(p00365~384), V08/V09/V11/V13/V44(p01179~1196,p01287~1289). R052~055/R057~058.
- 시작 Git: main, 로컬 HEAD/새 원격 main 조회 모두 12b536275b28b50429f81c4b85baea18d73ae358. 기존 문서·사용량 도구 변경은 보존.
- 시작 사용량은 요청 후 최초 조회 2026-10-08T05:54:53.505819+00:00, 주간 잔여 29%. 실제 rollout gpt-6-astra/medium. 기존 checkpoint P10-08 RUN_FINISHED, 중복 제품 실행 없음.

## 변경과 검증 연결
| 기준 | 실행 근거 |
|---|---|
| V08 역할 겹침, 차순위 채우지 않음 | RetentionExampleDatabaseChecks 5개 명시적 예제 중 동일 A 3역할 → 선정 ID 1개. 기존 PinReleaseDatabaseChecks에서 동일 파일 자동 3역할+고정 → 파일/슬롯 각 1개 |
| V09 미정·동률 | 예제에서 전부 미정, 미정 최신+티어 동률, 최신 시각 우선 검증. 기존 verifyLatest/verifyLowestTier의 unsigned UUID 경계도 유지 |
| V11 두 기기 9→10 경쟁 | PinReservationDatabaseChecks를 서로 다른 device/인증 정보로 보강. H2는 실제 세션 2개, MySQL은 다른 principal의 인증 경계 mock+실제 DB 트랜잭션. 한 요청만 성공, 총 10개 |
| V13 여러 보호 사유 | 기존 PinReleaseDatabaseChecks: 자동/고정/ORPHAN_KEEP/WAITING_LOCAL_CONFIRM, 바이트 1회, 해제 후 나머지 보호·파일 유지 |
| V44 여러 키·버전 | 예제에서 ORIGINAL/MALE/FEMALE·NORMAL/LIVE/MR를 한 곡에 섞어 곡 전체 3역할 및 중복 제거 검증 |
| 재연결 | 실제 RecordingLinking → 큐 → RetentionWorker 실행 후 원래/새 곡의 저장된 선정 행 직접 확인. 재연결·해제·다시 연결, 미정 역할 비움, 파일/명세 보존 |

- 새 예제: `services/api/src/test/java/com/ksh321/songrecord/api/retention/RetentionExampleDatabaseChecks.java`; H2 RetentionCandidatesTests와 실제 마이그레이션 MySqlIdempotencyTests에서 동일 실행.
- 기존 공유 검사/진입점: RecordingLinkingDatabaseChecks, RecordingLinkingTests, PinReservationDatabaseChecks, PinSlotsTests, RetentionJobDatabaseChecks, MySqlIdempotencyTests 수정.
- 제품 로직/API/스키마 변경 없음. 서버 예제 검증이므로 새 폰 실기 불필요.

## 로컬 검사와 별도 검토
- `services/api/gradlew.bat -p services/api test --console=plain`: BUILD SUCCESSFUL. 544개 중 477 PASS, 67 SKIPPED, 실패 0. MySQL 등 환경 조건부 67개는 통과로 계산하지 않음. 로그 `.local/workflow/p11-09/local-check.log`.
- 별도 검토에서 V11이 같은 기기 2요청이었던 공백 발견. 실제 두 기기로 보강 후 `test --tests '*PinSlotsTests' --console=plain`: 5 PASS. 로그 `.local/workflow/p11-09/pin-review-check.log`.
- 현재 모델이 원본 기대 결과·diff·검사 결과·계정/데이터 보존 대조. 예제 기대값은 제품 계산에서 생성하지 않음. 작업 실패를 삼킬 수 있는 worker의 반환값만 보지 않고 SUCCEEDED 및 저장된 역할을 직접 확인. 기존 검사를 삭제/약화하지 않음.
- 학습 개념: 선정 역할 수와 물리 파일 수는 다르며, 계정 단위 잠금은 서로 다른 기기의 고정 경쟁에도 적용되어야 한다. 큐 연결 검증은 결과 확인 중 재계산을 호출하면 누락된 처리를 가릴 수 있어 저장 결과를 직접 읽는다.

## 원격 검증
- 커밋·푸시 후 해당 SHA의 CI(서버·MySQL 마이그레이션)와 Idempotency MySQL 필수. 앱·공통 계약 변경 없어 Flutter/API contract는 영향 제외이며 통과 실적으로 세지 않음.
- 최종 완료·SHA·알림·사용량은 아래에 실제 결과로 추가한다.
