# P11-05 중복 제거와 버전 갱신

## 원본·범위
- 원본 계획 p00622~p00624, 설계 v1.11 6.1~6.3/11.5, R052~R055. P11-04 SHA106745964960701ffcf9308e2d1aafcf69a51ff4의 필수 CI 통과 후 착수했다.
- 기존 song_cloud_selection의 세 역할 열에 대응 관계를 저장한다. 저장된 역할 ID를 Set으로 읽어 합집합을 만들며 같은 ID는 1개다. 역할 중복을 다른 후보로 채우거나 키·버전별 추가 선정 행을 만들지 않는다. 기존 RecordingListing의 역할별 EXISTS와 snapshot 선정 테이블 읽기 계약을 보존한다.
- 최초 선정 revision=1, 역할 대응 관계가 달라질 때 +1, 동일 결과 재실행은 값·버전을 보존한다. 합집합이 같아도 역할 대응이 바뀌면 버전이 증가한다. 파일 명세는 SAVED 후 불변이므로 같은 역할 ID의 무변경 재실행에 새 파일 교체 버전을 만들지 않는다.

## 구현·동시성
- RetentionRoles.calculate가 하나의 후보 목록으로 대표·최신·최저와 ID 합집합을 계산한다. 기존 공개 역할 계산은 같은 비교 함수를 재사용한다.
- RetentionSelectionStore.recalculate는 신뢰된 내부 worker용이며 HTTP 인증 경계가 아니다. 외부 트랜잭션 참여를 거부하고 READ_COMMITTED 트랜잭션을 소유한다. USER_SYNC → SONG(AGGREGATE) → SONG_SELECTION 순으로 잠근다. 기존 계정 메타데이터 쓰기와 같은 USER_SYNC 잠금으로 계산 중 입력 변경을 직렬화한다.
- 활성 계정·소유 곡만 처리, 사라진 계정/다른 곡/비활성 곡은 저장하지 않는다. 동시 최초 생성과 재실행은 한 선정 행·같은 결과로 수렴한다. 역할 저장과 revision은 원자적이며 오류/overflow는 덮어쓰지 않는다.
- 파일·asset·pin·hold·용량 및 사용자 원본 변경 없음. 사건별 재계산 job 연결/변경 피드 후속은 P11-06, 물리 업로드·정리 및 고정은 후속 범위다. 이 기능은 내부 선정 저장 기반이며 사건 연결까지 완료했다고 주장하지 않는다.

## 검증·검토
- 변경: RetentionRoles.java, RetentionSelectionStore.java, RetentionCandidateDatabaseChecks.java, RetentionCandidatesTests.java, MySqlIdempotencyTests.java.
- 로컬 Gradle test --offline --no-daemon에서 RetentionCandidatesTests/RecordingLinkingTests/RecordingListingTests/LockOrderTests: 25 PASS, 실패/skip 0, 25초.
- 검토 보완 후 후보·선정 9개 재검증 PASS(19초): 활성 다른 계정 격리 추가, MySQL DROP CHECK와 H2 DROP CONSTRAINT 분리.
- 단일 파일 3역할·서로 다른 키/버전의 3역할·동일 합집합 역할 교체·최초 동시 생성·재실행 멱등·빈 선정·실제 SQL 제약 실패 롤백·버전 overflow·외부 트랜잭션 거부·파일 명세 보존을 검증한다. 실제 MySQL에서도 전체 마이그레이션 아래 같은 사례를 실행한다.
- 현재 Astra/medium 모델이 구현 후 별도 검토: 원본 합집합 기준, FK/계정 경계, 잠금 순서·단일 스냅샷 입력, 버전 조건, 기존 재연결·목록 회귀, 파일 무변경 확인. 별도 모델/에이전트 없음.
- 폰 실기 불필요. push 기준 main 106745964960701ffcf9308e2d1aafcf69a51ff4. 실제 CI 결과는 완료 후 아래에 기록한다. P11-05에서 승인 범위 종료한다.
