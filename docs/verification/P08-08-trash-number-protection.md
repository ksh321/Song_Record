# P08-08 휴지통 번호 보호

## 구현 범위

P08-02~04에서 마련한 생성 경로의 번호 예약과 CreationGuard 삭제 표식 검사를 재사용한다. TRASHED/PURGE_PENDING 오류에 실제로 안내할 기존 곡 ID와 revision을 추가하고, 실제 MySQL 생성 열·유일 제약·삭제 원장까지 포함하는 회귀 검증을 보강한다. 삭제/복원 API 및 삭제 작업자 자체는 후속 단계다.

POST /v1/songs에서 검증된 TJ 후보 번호를 같은 계정 범위에서 검사한다.

| 기존 상태 | 같은 번호로 생성 요청 | 번호 예약 |
|---|---|---|
| ACTIVE | 200 created=false, 기존 canonical_song_id | 유지 |
| TRASHED | 409 SONG_RESTORE_REQUIRED, 복원 안내 | 유지 |
| PURGE_PENDING | 409 SONG_PURGE_PENDING, 완료 대기 안내 | 유지 |
| PURGED | 새 UUID는 201 가능, 이전 UUID는 409 RESOURCE_PURGED | 해제 |

복원/대기 오류의 details에는 canonical_song_id, current_revision, lifecycle_state가 포함된다. 계정 범위에서 찾은 곡만 응답하며 요청의 제목/가수/버전 등으로 기존 곡을 덮어쓰지 않는다. retryable=false이므로 전송 오류처럼 자동 재시도를 반복하지 않고 사용자의 복원 또는 삭제 완료 이후 작업으로 처리한다.

## 번호와 UUID는 별개

V2의 reserved_tj_number 저장 생성 열과 (user_id,reserved_tj_number) 유일 제약이 휴지통·삭제 대기 번호도 예약한다. 번호는 문자열이어서 선행 0이 유지된다. PURGED가 되면 예약 값이 null이 되어 번호를 새 UUID로 재등록할 수 있다.

이전 UUID는 영구 삭제 자료의 식별자다. CreationGuard가 같은 계정의 UUID/삭제 원장을 번호 중복 조회보다 먼저 검사하므로, 같은 번호의 새 ACTIVE 곡이 있어도 이전 UUID 요청을 새 곡으로 매핑하지 않는다. 곡 행을 물리적으로 정리하고 멱등 영수증을 만료시켜도 deletion_ledger가 남아 이전 UUID의 부활을 막는다.

## 멱등과 롤백

휴지통 또는 삭제 대기 거절은 mutation_receipt를 남기지 않고 기존 곡·change_seq를 바꾸지 않는다. 삭제 완료 후에는 동일한 실패 요청 키와 새 UUID 요청을 다시 제출해 성공할 수 있다.

이미 성공한 생성 요청의 영수증이 남아 있다면 같은 키/본문 재전송은 당시 성공 응답을 그대로 반환한다. 과거 응답의 ACTIVE 표시는 현재 상태 재조회 결과가 아니다. 이 재전송은 실제 PURGED 행을 복원하거나 새 행을 생성하지 않는다. 영수증이 만료된 이후에는 같은 키라도 삭제 원장 검사로 RESOURCE_PURGED가 된다.

계정 sync 행 잠금으로 참여하는 생성/삭제 경로를 직렬화하고 DB 유일 제약으로 우회 삽입까지 막는다. 향후 삭제 작업자는 같은 잠금 규칙을 준수하고 PURGED 확정/삭제 원장 저장을 원자적으로 처리해야 한다.

## 검증

- SongLifecycleTests: H2 공통 수명주기 검사 및 HTTP 복원 안내 details/기존 제목 보존.
- SongLifecycleDatabaseChecks: TRASHED/PURGE_PENDING 생성 차단, 실제 유일 제약 거절, 실패 영수증/sequence 미변경, PURGED 새 UUID 생성, 이전 UUID 우선 거절, 성공 영수증 재전송 시 부활 방지, 물리 행/영수증 정리 후 삭제 원장 차단.
- MySqlIdempotencyTests: 실제 V2/V6/V10 테이블로 동일 시나리오 실행. 선행 0이 있는 TJ 번호 사용. 기존 Idempotency MySQL workflow에 포함된다.

수명 상태 전환과 행 정리는 테스트 SQL로 구성한 사전 조건이다. 삭제 API가 완성됐다는 의미는 아니다. V2를 포함한 기존 migration 변경이나 신규 migration은 없다.

적용 후 test bootJar, 푸시 후 CI / API contract / Idempotency MySQL을 확인한다. 모바일 재설치/실기 테스트는 필요 없다.
