# D09 — MySQL 임시 스냅샷
- 상태: 확정 / P00-07 / 2026-09-16
- 사용자 승인: 모든 추천 방법 채택, A안
- 관련: R040·R041, X10, P04-07·P07-05·P10
- 사례: [P00-07 공통 사례](../contracts/P00-07-examples.md)

## 보관 방식과 동일 시점
계정별 메타정보와 파일 명세를 MySQL 영속 보조 테이블에 복사한다. 음성 원본을 복사하지 않는다. 연결별 SQL TEMPORARY TABLE은 사용하지 않는다.
InnoDB REPEATABLE READ의 하나의 일관 읽기 트랜잭션에서 계정 change_seq와 대상 행을 모두 읽는다. 기준 cursor를 별도 시점 조회로 만들지 않는다. 기존 계정 change_seq 부여·업무 변경의 원자적 커밋 규칙을 전제로 한다.
읽기 결과는 별도 쓰기 연결로 BUILDING 영역에 분할 저장할 수 있지만 모든 원본 SELECT는 같은 읽기 뷰를 유지한다. 잠금 읽기나 INSERT SELECT의 다른 읽기 동작을 임의로 섞지 않는다. 다 읽은 후 읽기 트랜잭션을 닫고 행 수·해시·엔터티 완결성을 검증한 뒤 READY로 원자적으로 게시한다.
생성 중 실패하면 부분 결과는 조회 불가하며 새 읽기 뷰로 전체 재생성한다. 다른 시점의 페이지를 혼합하지 않는다. 생성 시간은 데이터량에 비례하므로 짧게 유지하도록 제한하고, 페이지 소비 시간 30분 동안 DB 트랜잭션을 열어두지 않는다.

## 보조 구조
| 테이블 | 핵심 필드 |
|---|---|
| SnapshotHeader | id, user_id, purpose(SYNC/EXPORT), status, schema_version, snapshot_cursor, captured_at, ready_at, expires_at, row_count, byte_count, manifest_hash, lease/attempt |
| SnapshotEntry | snapshot_id, entity, ordinal, resource_id, payload, payload_hash. (snapshot_id,entity,ordinal) 유일 |
| ExportSession | export_id, snapshot_id, include_trash, status, ready_at, expires_at |

상태: BUILDING → READY → EXPIRED → 정리, 생성 실패는 FAILED. 저장된 payload는 READY 이후 불변이다. 변경 로그·삭제 표식·필요한 관계도 일관된 기준으로 포함하며 공용 차트·인증 비밀은 제외한다.
초기 서버 설정: 계정당 BUILDING/READY 합계 2개, 스냅샷당 직렬화 payload 100MiB, 전체 논리 payload 1GiB, 생성 최대 10분. 이는 구현 운영 시작값이며 DB 인덱스·로그의 실제 디스크 비용까지 제한하는 값은 아니다. 슬롯/바이트 예약은 원자적으로 검사한다. 초과는 429 SNAPSHOT_CAPACITY_EXCEEDED로 재시도 안내하며 이미 소비 중인 사본을 몰래 교체하지 않는다.
만료 접근 차단은 요청마다 서버 시각으로 검사하고 청소 주기에 의존하지 않는다. 정리 작업은 5분마다 EXPIRED/FAILED와 lease가 만료된 부분 자료를 정리한다. 운영 용량 지표에는 임시 테이블·인덱스도 별도 포함한다.

## API·만료·재개
모든 경로 /v1, Bearer+device_id 인증·소유권 필요. token은 계정 인증을 대체하지 않는 불투명 식별자다.
- POST /sync/snapshots: {schema_version}, Idempotency-Key. 생성 중이면 202와 operation_id·조회 경로, READY 결과는 snapshot_token, snapshot_cursor, captured_at, ready_at, expires_at, 엔터티별 개수.
- GET /sync/snapshots/{token}: entity, cursor, limit(기본50/최대100). cursor는 사본·entity·ordinal에 귀속. payload는 해당 사본에서만 읽는다. 준비 전 409 SNAPSHOT_NOT_READY, 만료 410 SNAPSHOT_EXPIRED, 타인 사본 404.
- 만료 시각은 ready_at + 30분, 연장 없음. 같은 요청 재전송은 같은 작업/사본을 반환하며 TTL을 늘리지 않는다. 만료 후 새 사본은 새 op_id로 생성한다.
- 서버 재시작 후 READY는 남은 TTL 동안 재개 가능. BUILDING은 다른 읽기 트랜잭션에서 이어 읽지 않고 이전 attempt 부분 자료 폐기 후 전체 재생성한다.
- 앱은 수신 데이터를 별도 staging에 보관한다. 모든 엔터티 검증 후 로컬 기준 사본과 cursor를 한 트랜잭션으로 교체하고 로컬 미전송·충돌 초안을 보존한다. 부분 수신으로 현재 화면 DB를 덮어쓰지 않는다.
- 재개 가능한 로컬 수신 지점을 저장한다. 만료·잘못된 cursor는 새 사본으로 재시작하되 미전송 변경·녹음 파일은 삭제하지 않는다. 전체 사본 적용 뒤 snapshot_cursor 다음 변경부터 받는다.
- 탈퇴 접수 시 모든 사본·export 접근을 즉시 차단하고 정리 대상에 넣는다. READY에 과거 정보가 있다는 이유로 접근을 허용하지 않는다.

POST /exports와 GET /exports/{id}/manifest도 같은 사본 엔진·30분 TTL을 사용한다. 전체 manifest를 앱이 검증·고정해 받은 뒤 ZIP 생성과 파일 복사는 별도 로컬 작업이다. 음성 다운로드 시 현재 소유권·삭제·generation을 다시 검사한다. 단순히 스냅샷에 STORED라고 기록됐다고 다운로드를 보장하지 않는다.
D04 일반 목록의 조회 세대/커서와 이 스냅샷 토큰을 혼용하지 않는다. 실제 일관성·부하·재시작 테스트는 P07/P10에서 수행한다.
