# P07-09 공통 실패 검증과 UUID 재생성 차단

## 범위

P07 공통 기반의 응답 유실·동시 요청·영수증 정리 이후 재시도를 검증한다. CreationGuard를 추가해 같은 UUID의 기존 행 또는 영구 삭제 표식을 확인하기 전에 생성 콜백을 실행하지 않게 한다. 기존 IdempotentMutations와 RevisionChanges를 함께 검증한다.

실제 곡 생성 HTTP는 P08, 녹음 생성은 P09, 영구 삭제 실행 흐름은 P20/P23에서 이 기반에 연결한다. 이번 단계에서 이 기능들의 완성을 주장하지 않는다. DB 마이그레이션/모바일 변경/운영 데이터 정리 스케줄러는 추가하지 않는다.

## 서로 다른 세 가지 식별자

| 값 | 책임 | 유효 범위 |
|---|---|---|
| op_id와 요청 해시 | 같은 요청의 동시 실행을 직렬화하고 저장된 성공 응답 재전송 | 영수증이 존재하는 기간 |
| 자료 UUID와 기존 행 | 영수증이 사라져도 이미 만든 자료를 다시 만들거나 초기 입력으로 덮어쓰지 않음 | 자료가 존재하는 동안 |
| revision과 deletion_ledger | 오래된 수정 거절 / 물리 삭제한 UUID의 자동 부활 차단 | revision은 현재 행, 삭제 표식은 별도 영속 기록 |

90일은 과거 응답 영수증의 보관 기간이다. 90일이 지났다는 이유로 UUID가 새 자료가 되지는 않는다. 영수증 정리 후에는 동일한 과거 HTTP 응답을 복원한다고 보장하지 않는다. 현재 상태에 따라 기존 자료 결과 또는 충돌을 반환한다.

## 생성 경계

권장 호출 순서:

1. IdempotentMutations.execute에서 계정/op_id 영수증을 예약한다.
2. 전역 용량 변경이 필요한 업무라면 전역 잠금을 먼저 획득한다.
3. CreationGuard.create가 user_sync_state를 잠근다. 같은 계정의 생성/영구 삭제가 동일 잠금 규칙을 따라야 한다.
4. 계정·자료 종류·UUID의 deletion_ledger를 먼저 확인한다. 표식이 있으면 409 RESOURCE_PURGED, details={}, retryable=false다.
5. 기존 자료가 있으면 생성 콜백을 실행하지 않고 created=false와 현재 revision/state를 반환한다.
6. 표식과 기존 행이 모두 없을 때만 같은 트랜잭션에서 생성 콜백을 실행한다. 실제 기능은 콜백에서 AccountChanges.write로 자료 변경과 변경 로그를 함께 기록한다.

생성 검사는 계정 동기화 행 뒤에 AGGREGATE 순위를 등록한다. revision 서비스와 동일한 종류 순서(SONG, RECORDING, PLAYLIST, TAG)와 키를 쓴다. 삭제 표식은 locking read로 확인해 바깥 REPEATABLE_READ의 오래된 읽기 뷰를 그대로 믿지 않는다. DB PK/유일 제약도 유지한다.

기존 자료의 상태를 ACTIVE로 바꾸거나 편집값을 덮어쓰지 않는다. SONG의 TRASHED/PURGE_PENDING에 대한 SONG_RESTORE_REQUIRED/SONG_PURGE_PENDING 응답 매핑은 P08 도메인 서비스 책임이다. 기존 행과 표식이 모두 있는 비정상 중간 상태에서도 표식 검사를 우선한다.

CreationGuard는 신뢰된 서버 코드의 공통 진입점이다. UUID 문자열 파싱/요청 유효성 검사는 HTTP adapter에서 수행한다. 이미 잠근 동기화 행의 재획득은 허용되지만 전역 잠금을 뒤늦게 얻을 수는 없다. callback은 같은 데이터소스/트랜잭션을 써야 하며 외부 I/O와 REQUIRES_NEW를 넣지 않는다.

## 영수증과 실패 처리

- 커밋 전에 예외: 업무 변경과 영수증 예약 모두 롤백. 같은 op_id 재시도 가능.
- 커밋 후 응답 유실: 같은 op_id/본문 재요청은 저장된 성공 응답을 반환하며 업무 콜백을 다시 실행하지 않음.
- 같은 op_id/다른 본문: 영수증이 존재하면 IDEMPOTENCY_CONFLICT.
- 영수증 정리 후 같은 UUID 생성: 기존 자료를 유지하고 최신 revision/state를 이용해 응답. 이후 수정값을 생성 당시 값으로 덮어쓰지 않음.
- 영수증 정리 후 오래된 base_revision 수정: REVISION_CONFLICT.
- 영수증 정리 후 영구 삭제 UUID 재시도: 새 op_id로 바꾸어도 RESOURCE_PURGED.

기존 IdempotentMutations는 expires_at을 넘겨도 행이 남아 있으면 그 영수증을 재사용한다. 실제 보관 정리 후의 안전성을 테스트하기 위해 테스트 DB에서만 expires_at 조건으로 삭제한다. 운영 정리 스케줄러는 별도 단계다. 영수증이 남아 있는 동안 반환하는 과거 성공 응답은 현재 자료가 여전히 살아 있다는 증명이 아니며 재생성도 수행하지 않는다. 현재 상태는 조회/동기화로 확인한다.

## 검증과 한계

MutationFailureTests는 실제 JDBC 트랜잭션에서 응답 폐기 후 재요청, 91일 경과와 새 로그인 후 재시도, 수정값 보존, 물리 삭제 뒤 UUID 차단, 표식 우선, 휴지통/삭제 진행 상태 보존, 오래된 revision, 같은/서로 다른 op_id 경쟁, 생성 예외 롤백, 계정별 표식 범위를 확인한다. 응답 유실은 서버 커밋 후 반환값을 클라이언트가 받지 못한 상황을 재현한 것이며 실제 네트워크 장애 주입은 아니다.

MySqlIdempotencyTests에는 실제 V6 deletion_ledger DDL과 기존 영수증 불변 트리거를 적용한 만료 후 재시도/경쟁/삭제 표식 보존 검사를 추가한다. 곡 테이블은 이 공통 경계 검증에 필요한 최소 필드의 테스트 projection이다. 전체 곡 생성 규칙과 TJ 번호 충돌은 P08에서 실제 스키마로 추가 검증한다.

테스트의 직접 UPDATE/DELETE는 과거 수정/정리/삭제 완료 상태를 준비하기 위한 fixture다. 운영 삭제 구현은 표식 기록·자료 제거·AccountChanges 변경 기록을 같은 잠금과 트랜잭션으로 묶어야 한다. 임의 SQL이나 다른 잠금 규칙으로 우회한 업무까지 자동 보호하는 것은 아니다.

제작 환경에서는 MySQL 실행 환경이 없어 전용 테스트는 건너뛴다. 로컬 test bootJar 후 CI / API contract / Idempotency MySQL을 모두 확인한다. 테스트는 운영 DB가 아닌 자동 생성 테스트 DB만 사용한다.
