# P08-05b 내 곡 목록·검색 API

## 완료 범위

GET /v1/songs를 실제 DB 조회에 연결했다. P08-05a의 SR-SORT-1·5개 정렬·티어별 보기 규칙을 SQL keyset과 대조한다. 이번 단계에서 P08-05 서버 범위를 완료하며 모바일 화면 연결은 P17이다. GET /songs/{id}와 편집/삭제 API를 완료한 것으로 표시하지 않는다.

## 요청·응답

Authorization Bearer와 X-Device-Id로 계정을 확인한 뒤 입력을 검증한다. q, sort, view, limit, cursor만 받고 중복 매개변수와 알 수 없는 값은 400 VALIDATION_ERROR다. 기본 sort=ADDED_DESC, view=ALL, limit=50, 최대 100. q는 계약 공백 trim·NFC·ASCII 소문자화 후 최대 200 code points다.

소유 계정의 ACTIVE 곡만 검색한다. 제목 또는 가수의 정규화 UTF-8 바이트 부분 일치(LOCATE)를 사용하므로 %, _, !, 역슬래시는 문자 그대로다. DB의 accent/case-insensitive 기본 collation에 기대지 않는다. 외부 검색, 미등록 후보, 다른 계정과 휴지통은 섞지 않는다.

응답은 {items, count, next_cursor}. 각 항목은 기존 Song 필드와 created_at, latest_recorded_at을 포함한다. 최근 녹음이 없으면 latest_recorded_at=null, 마지막 페이지는 next_cursor=null이다. 응답 Cache-Control은 no-store다.

최근 녹음은 같은 계정·같은 곡의 ACTIVE·SAVED MAX(recorded_at)이며 recording_asset/기기 파일 테이블을 조회하지 않는다. 파일이 하나도 없는 녹음도 정렬에 포함된다. 녹음 없는 곡은 마지막, 모든 최종 동률은 unsigned UUID 오름차순이다.

## 일관된 읽기와 페이지 경계

P07 KeysetPages의 짧은 REPEATABLE_READ 트랜잭션 안에서 계정 change_seq, 검색 키 준비 상태, count, limit+1 행을 읽는다. 계정·정렬·보기·정규화 검색어·limit·키 버전이 커서에 결합된다. 조건 변경은 INVALID_CURSOR, 데이터 세대 변경/만료는 LIST_CURSOR_EXPIRED다.

정렬 컬럼과 ASC/DESC는 enum 기반 고정 목록에서만 선택한다. 사용자 값은 모두 바인드한다. 각 정렬 튜플에 대해 마지막 값보다 뒤인 OR 경계를 만들며 OFFSET이나 Java 전체 목록 정렬은 사용하지 않는다. 최근 녹음은 null 순위 + 시간 DESC + ID ASC로 분리하여 null 구간 경계를 처리한다. SQL 반환 순서는 기존 공통 튜플 comparator로 다시 검사한다.

count는 계정/ACTIVE/q 조건의 정확한 DB 결과 수다. 서버가 모르는 기기 파일 조건을 적용한 수가 아니다. 부분 문자열 검색, 복합 그룹 정렬, 최근 녹음 집계는 조건에 따라 스캔/filesort를 사용할 수 있다. keyset을 사용했다는 이유만으로 모든 정렬이 인덱스만으로 처리된다고 주장하지 않는다.

## 저장·업그레이드

V10 SQL은 song_query_key 파생 테이블과 곡 생성시각/녹음 최신시각 조회 인덱스를 추가한다. 제목/가수 정렬 키는 VARBINARY이며 소유자와 Song의 복합 외래 키를 유지한다.

V11 Java Flyway migration은 동일한 SR-SORT-1 구현을 사용해 기존 모든 곡의 키를 생성한다. UUID 기준 250개씩 읽어 메모리를 제한하며, 연결이 auto-commit이면 자체 DML 트랜잭션을 열고 실패 시 롤백한다. 사용자 제목·가수·버전·메모·revision·수정시각은 건드리지 않는다. migration checksum은 명시했고, 배포 후 V11과 V1 인코딩 의미는 바꾸지 않는다. 후속 규격 변경은 새 migration과 키 버전으로 처리해야 한다.

새 곡은 SongCreation의 기존 트랜잭션 안에서 곡·검색 키·출처·change_log·영수증을 함께 저장한다. 키 INSERT 실패도 전체 롤백한다. 기존 UUID/TJ 번호 중복 응답은 기존 키를 다시 쓰지 않는다. ACTIVE 곡의 키가 없거나 버전이 다르면 목록에서 조용히 누락하지 않고 503 SONG_INDEX_NOT_READY로 실패한다.

향후 P08-06의 제목/가수 편집은 같은 계정 잠금·트랜잭션 안에서 파생 키도 갱신해야 한다. 물리 삭제 시 파생 키를 먼저 제거해야 한다. SQL로 운영 song만 직접 바꾸는 비공식 쓰기 경로는 지원하지 않는다.

## 커서 키 설정

bootstrap 외 프로필은 유효한 32바이트 Base64 키를 요구하며 누락/오류는 시작 실패다. SONGRECORD_PAGINATION_KEY_BASE64를 application.properties에서 명시적으로 연결한다. 프로세스별 임시 키나 하드코딩된 운영 기본 키는 없다.

배포 ZIP 적용 스크립트는 Windows User 환경변수의 기존 키를 보존하고, 없으면 보안 난수로 생성하여 User 환경변수에 저장한다. 값은 출력하지 않는다. 적용 후 안내 PowerShell 블록은 부모 터미널에도 해당 키를 읽어 넣는다. 다른 기존 터미널/IDE는 새 환경을 읽도록 다시 시작하거나 이 환경변수를 읽어야 한다. 운영 다중 인스턴스는 별도 비밀 관리에서 같은 키를 주입한다.

CI의 기존 마이그레이션 검증 스크립트는 실행별 테스트 키를 생성한다. V9 데이터가 있는 상태에서 V10/V11 업그레이드와 키 누락 여부, 재시작을 확인한다. 개발 DB를 삭제/초기화하는 작업은 추가하지 않았다.

## 검증

- SongListingTests 6개: 실제 SQL의 5개 정렬×2개 보기/페이지 경계/최근 녹음 제외/검색, HTTP 응답과 커서·세대 변경, 인증과 계정 분리, 잘못된 입력과 키 누락, 키 저장 실패 롤백, 251개 기존 곡의 다중 배치 backfill.
- PaginationConfigurationTests 3개: 키 누락/오류 시작 실패, 올바른 키, bootstrap 예외.
- MySqlIdempotencyTests 2개 추가: 실제 V2+V10 테이블에서 동일 SQL 검증; 별도 빈 DB를 Flyway V9까지 올리고 기존 곡을 넣은 뒤 Java V11 자동 발견/키 내용/값 보존/재시작 검증.
- 기존 생성 MySQL 테스트 3개의 setup에 V10 키 테이블을 반영했다.
- OpenAPI에 GET /songs 구현 상태와 q/sort/view, count 및 목록 시각 필드를 반영했다.

제작 환경 test bootJar: 330 passed, 17 MySQL skipped, 0 failures. API 계약 검사 통과. 실제 MySQL 검증은 CI / Idempotency MySQL에서 확인해야 한다. 휴대폰 재설치나 UI 수동 테스트는 이번 단계에 요구하지 않는다.
