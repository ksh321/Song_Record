# P07-08 공통 목록 조회 계약

## 범위

기본 50 / 최대 100, 불투명 인증 암호화 커서, 안정적인 keyset 페이지 처리와 계정 조회 세대 검사를 구현한다. HTTP 곡 목록과 5개 정렬의 SQL/인덱스 연결은 P08-05, 녹음 조회는 P09에서 이 기반을 사용한다. 앱 화면과 DB 마이그레이션은 변경하지 않는다. 테스트 전용 page_item 테이블은 운영 스키마에 추가하지 않는다.

## 요청과 응답

- pageSize(null)은 50. 명시적인 limit는 1~100만 허용한다. 범위 밖은 400 VALIDATION_ERROR이며 100으로 조용히 자르지 않는다. 문자열 바인딩 오류는 HTTP adapter 책임이다.
- Query는 서버가 정한 resource(조회 종류와 부모 리소스 ID 포함), sort, keyVersion, 정규화된 filters JSON, limit를 받는다. 검색어/기간/필터/보기 모드/시간대처럼 결과에 영향을 주는 조건을 빠짐없이 포함해야 한다. 클라이언트 문자열을 SQL 컬럼이나 ORDER BY로 직접 사용하지 않는다.
- 누락 기본값 채우기, 태그 집합 정렬, 검색어 정규화 등 의미상의 정규화는 기능 adapter가 담당한다. CanonicalRequest는 JSON 객체 키 순서/수치 표현만 정리하며 배열 순서·누락/null·문자열 공백을 임의로 같게 만들지 않는다.
- Page는 items, count, next_cursor를 반환한다. count는 전체 일치 개수이며 현재 페이지 크기가 아니다. 빈 결과는 items=[], count=0, next_cursor=null. 마지막 페이지는 next_cursor=null이다.
- 빈 문자열 cursor는 첫 페이지의 생략과 다르며 INVALID_CURSOR다.

## 커서

PageCursor는 AES-256-GCM을 사용한다. 발급마다 SecureRandom 96비트 IV를 새로 생성하며 128비트 인증 태그와 전용 AAD를 쓴다. URL-safe Base64는 전송 형식일 뿐 보안 검증을 대신하지 않는다. 계정 UUID와 조회 조건의 SHA-256 fingerprint, 조회 세대, 마지막 정렬 튜플과 UUID, 만료 시각을 암호화한다. 커서는 계정 인증을 대신하지 않으며 매 요청의 세션 검증을 별도로 수행한다.

- 기본 수명 30분, 최대 길이 8192자. 같은 조건의 GET 재시도는 만료/세대 변경 전 재사용 가능하다.
- 다른 계정/조건/정렬/키 규격/limit, 변조/알 수 없는 형식/키 교체: 400 INVALID_CURSOR.
- 수명 만료 또는 계정 데이터 변경: 409 LIST_CURSOR_EXPIRED. 앱은 이전 페이지들을 폐기하고 첫 페이지부터 조회한다. 같은 커서 자동 재시도로 해결되지 않아 retryable=false다.
- 기존 동기화 로그의 CURSOR_EXPIRED와 구별한다. LIST_CURSOR_EXPIRED는 목록을 다시 읽으라는 뜻이며 전체 동기화 초기화 지시가 아니다.
- 토큰/조건/튜플 객체의 toString은 내용을 숨긴다. HTTP 계층에서도 검색어·커서 원문 로깅을 피한다.

## 조회 트랜잭션과 세대

KeysetPages는 기존 쓰기 트랜잭션 안에서 호출할 수 없다. 현재 세션을 검증하고, 페이지마다 15초 제한의 짧은 read-only REPEATABLE_READ 트랜잭션을 시작한다. 일반 SELECT로 user_sync_state.last_change_seq, COUNT, limit+1개 후보를 같은 읽기 뷰에서 읽는다. FOR UPDATE를 사용하지 않고 페이지 사이에 DB 연결이나 트랜잭션을 유지하지 않는다.

현재 세대는 계정 전체 last_change_seq다. 관련 없는 계정 데이터 변경에도 목록을 다시 시작할 수 있지만 변경 누락을 피하는 보수적 선택이다. 결과/정렬/개수에 영향을 주는 모든 업무 변경이 반드시 AccountChanges를 통해 같은 트랜잭션에서 이 번호를 올려야 한다. 향후 서버 파일 상태 변경도 이 규칙에 포함한다. 다른 DB나 읽기 복제본에서 세대와 행을 섞어 읽지 않는다.

조회 도중 다른 요청이 커밋하면 해당 페이지의 count/행은 기존 읽기 뷰로 일치한다. 다음 요청은 새 세대를 보고 이전 커서를 거절한다. 이는 D09의 여러 페이지 고정 스냅샷과 다르다. D09를 대체하거나 30분 DB 트랜잭션을 유지하지 않는다.

## 정렬과 keyset SQL

Source는 같은 JdbcTemplate, 계정 조건, 필터를 count/fetch에 사용한다. fetch는 전체 정렬 튜플에 대해 마지막 반환 항목보다 엄격히 뒤인 행을 최대 limit+1개 읽는다. 마지막 UUID는 unsigned 16바이트 순서다. 공통 compareUuid는 정규 UUID 문자열 순서로 이 규칙을 구현한다. Java UUID.compareTo의 signed long 순서를 사용하지 않는다.

예: rank 내림차순, UUID 오름차순이면 경계는 `(rank_no < :rank OR (rank_no = :rank AND id > :id))`, ORDER BY는 `rank_no DESC,id ASC`다. 모든 값은 바인드한다. limit+1번째 행은 다음 페이지 존재 확인용이며 다음 커서에는 마지막으로 실제 반환한 행을 넣는다. OFFSET을 사용하지 않는다.

Source.order는 SQL과 같은 방향/null 처리/정렬키를 사용해야 한다. 공통 계층은 반환 행이 경계보다 뒤인지와 엄격히 증가하는지를 검증하고 순서 오류를 거절한다. 제목/가수는 기존 SR-SORT-1, 티어별 보기의 선행 그룹, RECORDED_DESC의 null 마지막을 후속 adapter가 명시적으로 구현해야 한다. 공통 검사가 잘못된 SQL 필터나 누락된 행을 자동 증명하지는 않으므로 기능별 SQL/인덱스 테스트가 추가로 필요하다.

현재 기기 파일 조건은 D04대로 전체 동기화 로컬 DB에서 처리한다. 서버 한 페이지를 받은 뒤 기기 파일 조건으로 걸러 정확한 전체 count인 것처럼 표시하지 않는다.

## 키 설정과 연결 시점

PaginationConfiguration은 `songrecord.pagination.key-base64`가 명시될 때만 활성화된다. P07 단계는 아직 목록 HTTP endpoint를 연결하지 않으므로 기존 서버 실행 환경을 바꾸지 않아도 된다. P08 연결 시 `SONGRECORD_PAGINATION_KEY_BASE64`로 보안 난수 32바이트의 표준 Base64를 주입한다. 저장소/앱에 키를 넣거나 세션/OIDC 키를 재사용하지 않는다.

모든 서버 인스턴스는 같은 키를 사용한다. 같은 키면 재시작 후 유효 커서를 계속 읽을 수 있고, 키 교체 시 기존 커서는 거절되어 목록을 다시 시작한다. 하드코딩된 기본 키나 프로세스마다 달라지는 임시 키는 없다. 잘못된 키 설정은 해당 configuration 생성 시 실패한다. 실제 HTTP 연결 단계에서는 설정 누락 시 endpoint가 불완전하게 뜨지 않도록 필수 의존성으로 연결한다.

## 검증

PaginationTests: limit 경계, 동률 125건을 50/50/25건으로 순회, unsigned UUID 경계, 빈 결과/정확한 페이지 크기/limit=1, 다른 계정·조건·정렬·버전·limit 거절, 세대 변경, 변조/만료/길이 제한, null 튜플, 조건 정규화, 키 교체/같은 키의 재시작, 잘못된 Source 정렬, 기존 트랜잭션 금지.

MySqlIdempotencyTests에 실제 InnoDB의 count와 fetch 사이 다른 연결이 변경을 커밋하는 테스트를 추가했다. 첫 페이지는 기존 count/행을 유지하고 다음 요청은 세대 변경으로 거절되며 첫 페이지 재조회는 새 count/행을 반영해야 한다. 기존 Idempotency MySQL workflow에서 함께 실행한다.

제작 환경에서는 MySQL 전용 테스트를 실행하지 못한다. Windows 로컬 test bootJar 성공 후 CI / API contract / Idempotency MySQL 모두 통과해야 이번 단계 검증 완료다.

## 참고

- Java 21 Cipher: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/javax/crypto/Cipher.html
- MySQL 8.4 일관 읽기: https://dev.mysql.com/doc/refman/8.4/en/innodb-consistent-read.html
- 기존 계약: docs/decisions/D02-sort-order.md, D04-device-file-filter.md
