# P07-06 작업 등록과 실행

## 역할

기존 V6 job 테이블을 사용한다. JobQueue는 작업의 영속 등록, 선점, lease 갱신, 완료, 재시도를 담당하고 JobRunner.runOnce는 한 번의 처리 흐름을 실행한다.
SQL 마이그레이션, 모바일 파일, 운영 HTTP 허용 경로는 변경하지 않는다. 실제 업로드 검증/R2 삭제/정책 재계산/백업 대조 handler와 주기 실행 연결은 해당 기능 단계에서 구현한다. 이번 단계에서 빈 handler를 등록해 실제 작업이 성공한 것처럼 처리하지 않는다.

## 등록

- enqueue는 P07-03/05 업무 트랜잭션 안에서 호출해야 한다. 인증된 계정에서 user_id를 결정한다.
- 도메인 서비스는 aggregate 소유권/상태를 먼저 확인하고 payload를 서버에서 만든다. 임의 클라이언트 payload를 그대로 전달하지 않는다.
- dedupe_key는 계정(또는 GLOBAL), 작업 종류, aggregate UUID, 논리 작업 UUID를 조합해 SHA-256으로 만든다.
- 같은 키/동일한 정규화 payload는 기존 job ID를 반환한다. 다른 payload는 거절하며 바깥 업무 변경도 롤백한다.
- 완료된 작업에도 같은 키를 다시 쓰면 기존 ID를 반환한다. 새 작업은 새 논리 작업 UUID를 쓴다.
- enqueueMaintenance는 신뢰된 서버 전역 작업용이다. 일반 HTTP 요청에 노출하지 않는다.

## 실행과 복구

QUEUED 또는 RETRY_WAIT에서 run_after가 된 작업, 혹은 lease가 만료된 RUNNING 작업을 SELECT FOR UPDATE SKIP LOCKED로 선점한다.
등록된 handler가 처리할 Type만 claim하므로 알 수 없는 작업을 임의로 가져가지 않는다.
선점할 때 attempt_count와 revision을 증가시키고 새 lease_token을 발급한다. 기본 lease는 2분, 최대 5회이며 생성자로 정책을 주입한다.

- prepare는 DB 트랜잭션 밖에서 실행한다. 길어지는 작업은 만료 전에 queue.renew를 호출하고 false면 중단한다.
- prepare가 반환한 DB 변경 콜백은 complete 안에서 현재 lease 소유권 확인 후 실행된다.
- 콜백과 SUCCEEDED 변경은 같은 트랜잭션이다. 완료 중 만료/오류가 나면 DB 효과도 롤백한다.
- 중복 완료 또는 만료된 옛 토큰의 완료/재시도/갱신은 false로 거절한다.
- 처리 실패는 RETRY_WAIT 후 5,10,20,...초(최대 300초) 대기한다. 최대 시도에 도달하면 FAILED다. 명시적 영구 오류는 fail(lease,false)로 종료할 수 있다.
- 실행자 중단 시 lease 만료 후 새 실행자가 처음부터 재시도한다. 외부 작업의 바이트 단위 진행 재개를 자동 제공하지는 않는다.
- 오류 원문/URL/인증정보를 last_error에 저장하지 않고 고정 코드만 기록한다.
- 모든 실행자 서버의 UTC 시계가 동기화되어 있어야 한다. 운영 시 시계 동기화와 lease보다 짧은 I/O 시간 제한/heartbeat를 설정한다.

## 중복 실행 범위와 잠금

이 큐는 중복 실행을 전제로 한다. 외부 I/O와 DB는 하나의 트랜잭션이 아니므로, 외부 효과는 generation/operation ID 같은 안정적 식별자로 도메인 handler 자체가 멱등하게 만들어야 한다. 큐만으로 R2 등의 외부 효과가 정확히 한 번 발생한다고 주장하지 않는다.
DB 완료 콜백은 동일한 데이터소스/트랜잭션을 사용하고 REQUIRES_NEW와 외부 I/O를 넣지 않는다. 사용량/상태 반영 전 도메인 generation과 revision을 다시 검사한다.
큐 lease 행을 잠근 상태에서 완료 도메인 잠금을 획득한다. 후속 P07-07에서 도메인→같은 job 행의 역순 접근을 피하도록 전체 경로를 정리한다. 완료 콜백에서 실행 중인 자기 job을 재등록하지 않는다. 여러 작업/도메인을 묶을 때 전역→계정 동기화→권한/용량 등 기존 도메인 순서도 유지한다.

## 이전 멱등 처리 수정

V6의 trg_receipt_before_update는 모든 mutation_receipt UPDATE를 금지한다. P07-03은 임시 행을 INSERT한 뒤 UPDATE했고, MySQL 테스트가 DDL만 가져오고 이 트리거를 포함하지 않아 문제를 놓쳤다.
이번 변경은 자기 트랜잭션에서 만든 미커밋 임시 행만 DELETE하고 최종 결과를 INSERT한다. 유일 키 잠금은 커밋까지 유지되고, 최종 결과와 업무 변경은 함께 확정된다. 이미 커밋된 결과의 재시도 경로는 읽기만 수행한다. 트리거/기존 마이그레이션은 바꾸지 않는다.
MySQL 테스트에는 실제 V6의 receipt/job 트리거도 설치하며, 커밋된 receipt의 UPDATE가 계속 거절되는지 확인한다.

## 검증

JobTests: 계정별 dedupe, 다른 payload 거절, 업무/등록 일괄 롤백, 중복 완료 효과 1회, lease 만료 인계, 옛 실행자 차단, heartbeat, 재시도 대기/한도, 반복 중단 한도, 완료 실패/완료 중 만료 롤백, prepare의 트랜잭션 분리, 오류 원문 비저장, 두 실행자의 경쟁 선점.
MySqlIdempotencyTests: 실제 V6 job 테이블과 trigger에서 동시 선점·만료 인계·옛 실행자 차단·중복 완료와 업무/job 일괄 롤백. 기존 receipt 재시도 테스트도 불변 trigger가 있는 상태로 실행한다.
Windows 스크립트는 test bootJar를 실행한다. 실제 MySQL 검사는 기존 Idempotency MySQL workflow에서 실행한다. CI / API contract / Idempotency MySQL 모두 초록불인지 확인한다.

## 이해 확인

lease는 작업 처리 권한의 유효시간이다. 실행자가 멈추면 시간이 지난 뒤 다른 실행자가 이어받는다. lease_token은 같은 작업의 새 실행자와 옛 실행자를 구분한다. dedupe_key는 같은 논리 작업이 중복 등록되는 것을 막는다.
