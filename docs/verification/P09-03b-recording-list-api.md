# P09-03b 녹음 목록 DB 조회 API

## 구현

GET /v1/recordings를 implemented로 전환한다. P09-03a의 기간·곡/미연결·키·버전·티어/미정·컨디션·태그 AND·서버 파일·DRAFT/SAVED 필터와 네 가지 정렬을 parameterized SQL에 연결한다. 인증 계정의 ACTIVE 녹음만 조회하며 본문/쿼리로 다른 소유자를 지정할 수 없다.

응답은 items, count, next_cursor다. count는 서버에서 같은 필터로 계산한 전체 메타정보 개수이며 items/개수/태그를 하나의 REPEATABLE_READ 읽기 트랜잭션에서 조회한다. 마지막 cursor는 null, Cache-Control은 no-store다. 기존 공통 KeysetPages를 사용해 인증 세션/계정·전체 조건·정렬·limit·정렬 규격·계정 change_seq에 커서를 결합한다.

## DB 필터·페이지·정렬

RecordingListRules의 메모리 판정기는 테스트 기준으로만 사용한다. 실제 API는 필터를 WHERE에 적용한 후 COUNT와 LIMIT(limit+1) keyset 조회를 수행한다. OFFSET이나 전체 행 로딩 후 후처리를 사용하지 않는다.

- 최신순/오래된순: recorded_at DESC/ASC, 최종 id ASC.
- 곡명순: Recording.title_snapshot에서 만든 VARBINARY title_key ASC, id ASC. 연결 Song 제목은 사용하지 않는다. null 제목은 빈 문자열 정렬 키로 마지막에 배치한다.
- 티어순: S/A/B/C/D/미정 rank ASC → recorded_at DESC → id ASC.

동률은 unsigned BINARY UUID 순서를 사용하며 커서 비교기도 같은 규칙이다. 태그 필터는 태그별 EXISTS로 AND 적용하므로 태그가 여러 개여도 녹음 행/개수를 중복시키지 않는다. 반환 페이지 태그는 최대 limit+1개 녹음에 대한 한 번의 묶음 조회로 가져온다.

## 파일 상태

파일 명세나 cloud asset 행이 없어도 기본 목록에 녹음 정보가 남는다. LEFT JOIN을 사용하고 cloud 행이 없으면 state=NONE, stored=false, blocked_reason=null이다. server_file=PRESENT는 STORED/DELETING이며 stored_at이 있는 행으로 정의한다. DELETING은 삭제 확인 전 DB에 남아 있는 서버 사본 상태이며, 그 상태로 안전한 재생 URL을 발급할 수 있다는 뜻은 아니다. ABSENT는 그 반대다. QUEUED/UPLOADING/VERIFYING만으로 저장 완료라고 표시하지 않는다.

cloud.desired_reasons는 저장된 song_cloud_selection과 현재/대기 pin_slot을 조회한다. 이는 실제 파일 존재와 독립이며 이 API가 정책을 재계산하지 않는다. 향후 작업자가 서버 파일/보관 정책 상태를 변경할 때도 계정 change_seq를 함께 갱신해 기존 페이지 커서를 무효화해야 한다. 현재 기기의 파일 유무는 서버가 추정하지 않는다.

## V12·V13 마이그레이션

V12는 recording_query_key 테이블과 소유자/제목/ID 인덱스를 생성한다. V13 Java Flyway migration은 기존 모든 녹음을 UUID keyset 250개씩 읽어 title_snapshot 정렬 키를 채운다. 원래 녹음 정보/파일/revision은 바꾸지 않는다. 실패 시 재실행 가능한 DELETE+INSERT backfill이며 기존 migration을 수정하지 않는다.

새 DRAFT 생성에서 키를 함께 INSERT하고 SAVED 전환에서 최종 제목으로 키를 교체한다. 모두 녹음 변경·파일 명세·로그와 같은 트랜잭션이다. 향후 일반 제목 수정도 이 유지 규칙을 따라야 한다. 활성 녹음에 키가 없거나 규격이 다르면 RECORDING_INDEX_NOT_READY(503)를 반환하여 조용한 누락을 방지한다.

정렬 키 규격은 현재 SR-SORT-1/SR-SORT-BYTES-1이다. 이미 적용한 backfill/인코더 의미를 이후 임의 변경하지 않고 새 규격과 migration으로 전환해야 한다.

## 검증

RecordingListingDatabaseChecks 공통 기준 검사를 H2와 실제 전체 Flyway MySQL 스키마에서 실행한다. 네 정렬 × 14개 필터 조합을 limit=2로 끝까지 읽어 P09-03a 기준 목록/순서/개수와 비교한다. null 제목·동률·unsigned UUID·파일 없음·STORED/QUEUED·태그 AND·복합 조건·보관 사유를 포함한다.

RecordingListingTests 4개: 위 SQL 비교, HTTP 인증/계정 격리/파일 없는 개수/변경 후 커서 만료, 251행 다중 배치 backfill·재실행·원본 보존, SAVED 제목 키 갱신·실패 시 키 롤백·기존 커서 무효화.

MySqlIdempotencyTests에 전체 V1~V13 migration 후 SQL 비교 검사를 추가하고, 기존 V9 업그레이드 검사에는 녹음 한 건을 미리 넣어 V13 키 생성과 원본 보존을 검증하도록 확장했다. 기존 DRAFT/SAVED MySQL fixture도 실제 V12 키 테이블을 사용한다. 마이그레이션 CI 스크립트는 최종 V13 및 곡/녹음 키 누락 없음과 재시작을 확인한다.

제작 환경은 MySQL 전용 검사를 건너뛴다. 푸시 후 CI / API contract / Idempotency MySQL을 모두 확인한다. 로컬 test bootJar와 API 계약 검사를 실행한다.

## 적용

V12/V13은 새 서버를 시작할 때 Flyway가 자동 적용한다. 실행 중인 Spring Boot는 새 코드로 재시작해야 한다. 수동 SQL 실행이나 파일 이동은 필요 없다. 모바일 UI 연결·로컬 오프라인 목록·후속 정책 재계산 작업자는 이번 범위가 아니다.
