# P07-07 공통 잠금 순서

## 목적과 적용 범위

요청이 자료를 잠근 뒤 job을 등록하는 반면 작업 완료가 job을 잠근 뒤 같은 자료를 수정하면 서로 기다리는 교착 상태가 생길 수 있다. 참여하는 명시적 잠금의 순서를 통일하고 역순 접근을 트랜잭션 오류로 처리한다.

SQL 마이그레이션과 모바일 변경은 없다. StorageLocks는 후속 업로드/정책 서비스가 사용할 공통 진입점이다. 실제 객체 전송/삭제 handler와 scheduler를 이번 단계에서 추가하지 않는다.

## 잠금 규칙

필요한 행만 아래 순서로 획득한다. 사용하지 않는 중간 단계는 건너뛸 수 있다.

| 순위 | 대상 | 진입점 |
|---|---|---|
| 1 | global_storage_usage | StorageLocks.global |
| 2 | user_sync | AccountChanges |
| 3 | user_entitlement | StorageLocks.owned ENTITLEMENT |
| 4 | storage_usage | StorageLocks.owned USAGE |
| 5 | song / recording / playlist / tag | RevisionChanges |
| 6 | song_cloud_selection | StorageLocks.owned SELECTION |
| 7 | pin_slot | StorageLocks.pin |
| 8 | recording_asset | StorageLocks.owned ASSET |
| 9 | job | JobQueue |

같은 순위에서는 안정적인 문자열 키의 오름차순으로 획득한다. aggregate 키는 계정 UUID / 종류 순번(SONG, RECORDING, PLAYLIST, TAG) / 자료 UUID다. UUID는 문자열 순서로 정렬하며 pin 번호는 10자리 0 채움으로 숫자 순서를 보존한다. 이미 등록한 정확히 같은 행의 재획득은 허용한다.

작업 등록 여러 건을 한 트랜잭션에서 수행할 때는 dedupe SHA-256의 16진수 키 순서가 필요하다. 현재 단건 등록 진입점은 입력 목록을 자동 정렬하지 않는다. 작업 완료 콜백에서 자기 job을 재등록하지 않는다. claim/renew/fail/complete는 바깥 트랜잭션을 금지하고 각각 독립적으로 한 job을 처리한다. claim은 대상을 SELECT FOR UPDATE SKIP LOCKED로 정한 직후 순서를 등록하며, 이 시점에 다른 도메인 잠금은 없다.

전역 용량 변경이 필요하면 기존 업무 트랜잭션에서 global을 먼저 호출한 뒤 AccountChanges로 들어간다. AccountChanges 콜백 안에서 뒤늦게 global을 요청하면 실패한다. StorageLocks는 같은 데이터소스의 기존 트랜잭션 참여를 요구하고 계정 소유 행을 재검증한다. 다른 계정 자료는 일반 RESOURCE_NOT_FOUND 404다.

LockOrder 상태는 Spring 트랜잭션에 묶는다. 커밋/롤백 후 정리하고 REQUIRES_NEW에서는 바깥 상태를 보류했다가 복구한다. 역순 예외를 호출자가 잡아도 beforeCommit에서 다시 거절해 부분 변경이 커밋되지 않게 한다. 오류 메시지에 계정/자료 ID를 넣지 않는다. REQUIRES_NEW 지원은 추적 상태의 분리를 뜻하며, 바깥 트랜잭션이 잡은 행을 안쪽에서 기다리는 설계를 허용한다는 뜻이 아니다.

## 작업 완료의 경쟁 처리

1. complete가 유효한 lease인지 잠금 없는 SELECT로 확인한다. 이미 만료/인계됐다면 false다.
2. DB 전용 콜백이 필요한 도메인 잠금을 순서대로 획득하고 변경한다.
3. 마지막에 job을 UPDATE하면서 RUNNING 상태, lease_token, lease_until을 다시 검사한다.
4. 영향받은 행이 1개이면 자료 변경과 SUCCEEDED를 함께 커밋한다. 0개이면 예외로 전체 롤백한다.

예를 들어 옛 실행자가 자료를 수정하는 동안 lease가 만료되어 새 실행자가 claim할 수 있다. 옛 실행자는 마지막 token 검사에서 실패하고 자료 변경을 되돌린다. 새 실행자만 자신의 token으로 완료할 수 있다. 콜백이 호출됐다는 사실과 변경이 커밋됐다는 사실은 다르다.

DB 콜백은 반드시 같은 데이터소스/트랜잭션을 사용해야 한다. REQUIRES_NEW, 다른 DB, 네트워크 전송, 객체 삭제 등은 이 롤백으로 되돌릴 수 없다. 외부 작업은 JobRunner.prepare에서 트랜잭션 밖에 실행하고 안정적인 operation/generation으로 멱등성을 확보한다. prepare 직전에 활성 트랜잭션이 없는지 검사한다. 도메인 generation/revision 재검증은 각 handler의 책임이다.

## 한계

LockOrder는 참여 서비스의 명시적 잠금만 추적한다. 임의 JDBC SQL, 외래 키/인덱스/트리거의 암묵적 잠금과 다른 DB 연결을 자동 감시하지 않는다. 인증 서비스의 별도 잠금 경로도 이번 변경 대상이 아니다. 멱등 receipt 예약은 기존처럼 업무 변경 전에 요청 키 하나를 직렬화하며, 업무 도중 다른 요청의 receipt를 추가 획득하지 않는다.

따라서 모든 MySQL 교착 상태가 사라진다는 보장은 없다. 운영의 교착 상태/잠금 시간초과 관찰과 안전한 전체 트랜잭션 재시도 정책은 여전히 필요하다. 용량 잠금은 정책 계산/DB 반영 동안만 유지하고 외부 I/O 동안 유지하지 않는다. 아직 없는 업로드/삭제 구현의 동작까지 검증했다고 주장하지 않는다.

## 검증

- LockOrderTests: 순방향/역방향, 동일 순위 정렬, 재획득, 예외를 삼킨 경우 롤백, 종료 후 정리, REQUIRES_NEW 복구, 트랜잭션 경계, 실제 StorageLocks와 소유권.
- JobTests: DB 효과 도중 lease 인계가 가능하고, 옛 실행자의 효과는 롤백되며 새 실행자만 완료하는 경쟁 상황.
- MySqlIdempotencyTests: 실제 마이그레이션의 전역 용량 테이블과 job 트리거를 사용해 순서 위반 롤백 및 완료 도중 lease 인계를 검증한다.
- 제작 환경: 전체 273개 중 264개 통과, MySQL 전용 9개 환경 미제공으로 건너뜀. test bootJar 및 API 계약 검증 통과.
- Windows 적용 스크립트: test bootJar. 실제 MySQL 실행은 기존 Idempotency MySQL workflow가 담당한다. 푸시 후 CI / API contract / Idempotency MySQL을 모두 확인한다.
