# P11-06 재계산 사건 연결

- 승인: 2026-10-08 P11-08까지 원수. 현재 대화 Astra/medium 직접 구현·검토, 별도 AI 호출 없음.
- 원본: 코드구현계획서 v1.0 P11-06 (검색 p00625~627), 구현설계서 v1.11 자동 보관 선정 규칙; P11-01~05 완료 근거 유지.
- 변경: RevisionChanges와 AccountChanges가 SAVED·티어·대표·곡 연결·녹음/곡 lifecycle 변경을 수집하고 동일 트랜잭션에서 JobQueue에 등록한다. 기록 시각 변경은 기존 RecordingEditing 연결 유지. 곡별 중복 이벤트는 한 batch 안에서 합친다.
- 실행: RetentionScheduling이 기존 durable queue를 소비한다. USER_SYNC 잠금 후 최신 DB 값으로 선정하고, 선정 저장과 작업 완료를 같은 READ_COMMITTED 트랜잭션에 묶는다. 늦은 작업의 payload로 과거 선정값을 덮어쓰지 않는다. lease 만료 시 선정 저장도 롤백한다.
- 삭제/복원 범위: 공통 RevisionChanges 경유 lifecycle 변경과 worker 연결을 검증했다. 후속 P20 삭제 UI/API 전체를 구현했다는 뜻은 아니다. 물리 파일·asset·pin·hold 삭제 없음.
- 로컬: Gradle test 일괄 실행 (`*Retention*Tests`, `*RecordingSavingTests`, `*SongRepresentativeTests`, `*RecordingEditingTests`, `*RecordingRatingTests`, `*RecordingLinkingTests`, `*JobTests`, `*RevisionTests`, `*AccountChangesTests`) 83개 통과, 실패/skip 0. 로그 `.local/workflow/p11-06/local-check.log`.
- 기존 3개 공유 회귀는 SAVED 이벤트 1개가 추가되는 새로운 요구에 맞춰 기대 개수를 변경했다. 실패 rollback은 기존 저장 이벤트만 남는지, replay/no-op은 작업이 증가하지 않는지 계속 확인한다.
- 검토: 현재 모델 별도 diff 검토. 계정 격리, lock 순서, 이벤트 rollback, lease fence, 과거 작업, lifecycle 복원, 파일 보존 확인. MySQL 부분 fixture에 필요한 job 테이블 추가. 실제 MySQL 통합은 필수 CI에서 확인한다.
- 서버 내부 연결 변경이므로 별도 폰 실기 불필요. 필수 원격 CI 통과 전 완료 아님.
- 학습: 작업 큐에는 과거의 계산 결과보다 재계산할 대상만 담고, 실행 시 현재 상태를 읽으면 늦은 작업의 역전 적용을 막을 수 있다.

## CI 회귀 보완
- 62614431ec1298585823c21738dc267d8476b314: 실제 MySQL 통과, 일반 CI의 SongApiIntegrationTests 1개 실패. 대표 변경 이벤트를 추가하면서 해당 임시 fixture의 job 테이블이 누락된 원인 확인.
- 해당 fixture 보완 후 로컬 서버 전체 Gradle test: {'tests': 533, 'failures': 0, 'errors': 0, 'skipped': 67}; skip은 MySQL 전용 환경 조건이며 통과로 계산하지 않음. 로그 `.local/workflow/p11-06/local-full.log`.
- 현재 모델 재검토: 제품 로직 변경 없이 테스트 환경만 보완. 최종 SHA CI 재확인 필요.
