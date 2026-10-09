# P13-05 삭제 직전 재검사 (원수)

- 계획 p00696~697, 설계 p00435~437/p00739~741, R061/R062/V17. P13-04 a0a8d6d06fb30affad7c511abe72e5b648b999b5 필수 CI PASS 후 finish→begin. 요청·관측 Sol6.1/medium 사용자 고정.
- CleanupAuthorizations: USER_SYNC→현재 소유 asset→확인 행 순서의 짧은 READ_COMMITTED 트랜잭션. CONFIRMED의 유효 기간·계정/녹음 활성 SAVED·generation/hash/revision·실제 최신 자동 역할·current/pending 고정·CloudHold를 재검사한다. 만료는 EXPIRED, 객체 변경/새 보호는 CANCELLED이며 기존 서버 사본·hold·사용량은 유지한다.
- 유효한 무보호 객체만 WAITING_LOCAL_CONFIRM/정리 가능한 ORPHAN_KEEP 해제→DELETING 및 revision 증가→RECORDING_ASSET 변경 피드→계정 소유 ASSET_DELETE Job 등록을 한 트랜잭션으로 수행한다. PENDING_REPLACEMENT/자동 역할/고정은 강제 해제하지 않는다. 새로운 JobQueue.enqueueOwnedMaintenance는 저장된 서버 도메인에서만 호출하며 공개 작업 제출 API가 없다.
- RetentionScheduling의 기존 60초 단일 스케줄러에 100건 cursor 방식의 확인 처리 연결. 기존 고정 API의 USER_SYNC 직렬화/DELETING 거절과 결합. 중복 authorize는 작업·이벤트를 늘리지 않는다. R2 호출/used 차감은 하지 않으며 P13-06에서 실제 삭제를 확정한다.
- 로컬 일괄 gradlew test bootJar --offline: 전체607 중529 PASS/조건부77/새 fixture 1 FAIL(63초). H2 CHECK 생성 연결을 닫으면 검사가 닫힌 session을 참조한 fixture 문제이며 keeper를 검사 동안 유지하도록 수정. CleanupAuthorizationTests 및 bootJar 영향 재검사 PASS11초. 검사·DB 제약 제거 없음. 최초 ResourceDatabasePopulator 인수 타입 컴파일 오류도 올바른 Connection 사용으로 수정.
- 동일 shared checks를 완전 migration MySQL 검사에 등록: 먼저 승인된 실제 pins.reserve→CANCELLED, DELETING 뒤 실제 pins.reserve→FILE_CLEANUP_IN_PROGRESS, 최신 역할/PENDING_REPLACEMENT/만료/새 generation 거절, 동시 두 요청의 안전한 결과, 작업 등록 실패 시 상태·hold·이벤트 원자 rollback, 중복 Job 없음, 녹음 정보 ACTIVE/used 불변 대조. 로컬 Docker 엔진 미실행이므로 실제 MySQL은 현재 SHA CI에서 확인한다.
- 현재 모델 별도 검토: 원본 완료 기준·diff·검사·잠금 순서·계정/객체 범위·revision·토큰 기간·hold 구분·job dedupe·원자 rollback·변경 피드의 키/URL 제외·파일 I/O 분리·기존 데이터 보존 대조 완료. 방어적 null confirmation_mode 판정도 추가했다. 새 폰/플랫폼 변경 없음, 직접 조작 요구 없음.
- 서버 변경 영향 CI만 필요. 앱/계약 재검사는 NOT_APPLICABLE이며 통과 실적으로 세지 않는다. 푸시 직전 원격 HEAD a0a8d6d를 BaseCommit으로 확인. 최종 SHA 서버·MySQL CI 대기.
- 학습: 삭제와 고정은 같은 계정 잠금으로 순서를 정해야 한다. 확인과 작업 등록을 분리된 트랜잭션으로 처리하면 중간 실패로 보호만 사라질 수 있으므로 함께 확정한다.

- MySQL 제약 재대조에서 PENDING_REPLACEMENT 시험 데이터에 related_operation_id/required_selection_revision가 필요함을 확인. 실제 V5 제약을 H2 fixture에도 추가하고 올바른 연관 값을 넣었다. hold-constraint-review 검사 PASS8초. 제품 보호 논리 변화/제약 완화 없음. 최초 8c6c5f1 대신 최종 수정 SHA CI로 검증하며 이전 감시 기록 보존.
