# P08-05a 내 곡 검색·정렬 규칙과 DB 정렬 키

## 범위와 완료 기준

P08-05를 a(검색·정렬 계약과 키 검증), b(운영 DB와 GET /songs 연결)로 나눈다. 이번 변경은 a이며 GET /songs는 아직 planned다. 기존 생성 API, 운영 DB 스키마, 모바일 화면은 변경하지 않는다. P08-05 전체 완료로 표시하지 않는다.

근거: 설계서 2.1.1~2.1.2, D02 SR-SORT-1, P07-08 커서 계약. 결과물은 SongListRules, DomainOrdering.sortKeyBytes, fixtures/songs/list-order.json과 공통 DB 검증 코드다.

## 검색 계약

SongListRules.Query는 q의 앞뒤 계약 공백 제거, 기존 DomainOrdering의 NFC 정규화, ASCII 영문 소문자화를 공유한다. 내부 공백·구두점·악센트·전각 문자는 유지한다. 정규화 후 최대 200 Unicode code points, null 또는 공백만 있는 검색어는 전체다. 제목 OR 가수의 문자 그대로 부분 일치이며 별칭 확장이나 외부 검색 호출은 없다.

includes(owner,row)는 소유자 일치와 ACTIVE를 모두 요구한다. 이는 도메인 판정 함수이며 인증을 대신하지 않는다. b의 SQL adapter는 인증에서 얻은 계정을 count/fetch 양쪽 WHERE에 적용해야 한다. Java로 계정 전체 목록을 읽고 메모리에서 페이지를 자르는 API는 구현하지 않는다.

SQL LIKE에 사용할 때는 likePattern()을 바인드하고 ESCAPE '!'를 명시한다. %, _, !를 이스케이프하므로 사용자 입력이 와일드카드가 되지 않는다. 이 함수만으로 DB collation이 맞춰지지는 않는다. b에서 정규화 검색 열과 비교 방식을 연결하고 HTTP/SQL 결과를 같은 사례로 검증해야 한다.

## 정렬과 커서

| sort | 비교 순서 |
| --- | --- |
| ADDED_DESC | created_at 내림차순 → unsigned UUID |
| RECORDED_DESC | 최신 eligible recorded_at 내림차순, 없으면 마지막 → unsigned UUID |
| TIER | S/A/B/C/D/미정 → SR-SORT-1 곡명 → unsigned UUID |
| TITLE | SR-SORT-1 곡명 → unsigned UUID |
| ARTIST | SR-SORT-1 가수 → SR-SORT-1 곡명 → unsigned UUID |

기본 sort=ADDED_DESC, view=ALL, limit=50이며 limit는 1~100이다. TIER_GROUPED는 S/A/B/C/D/미정 그룹을 먼저 고정하고 그룹 안에 선택 정렬을 적용한다. 알 수 없는 sort/view는 거절한다. Query.parse는 다음 단계 HTTP adapter가 사용할 계약이며 현재 URL 매개변수가 추가된 것은 아니다.

최근 녹음 후보는 같은 계정·같은 곡의 ACTIVE·SAVED만 인정한다. DRAFT, 휴지통·삭제 상태, 다른 계정/곡, 미연결 녹음은 제외한다. Recording 입력 자체에 서버/기기 파일 상태를 두지 않아 파일 상태로 순위가 달라지지 않도록 한다. b에서는 동일 조건의 MAX(recorded_at) SQL로 연결한다.

cursorQuery는 계정 외에 검색어·정렬·보기·limit·키 버전을 커서 지문에 넣는다. 검색어 앞뒤 공백·ASCII 대소문자만 다른 요청은 같은 조건이다. 정렬 튜플은 DB 키의 긴 16진 표현 대신 원문 표시 문자열을 암호화 커서 안에 넣고, 비교 시 공통 규칙을 적용한다. 최종 UUID 비교에는 Java UUID.compareTo를 사용하지 않는다.

## DB용 SR-SORT-BYTES-1

DomainOrdering의 기존 SR-SORT-1 구조화 키를 그대로 인코딩한다. 비교 의미와 NFC 구현은 바꾸지 않는다. 기본 DB 문자 collation으로 한글·자연수를 정렬하지 않는다.

- 첫 바이트: 문자 그룹 0~4.
- 숫자 토큰: 표식 1 + 선행 0 제거 후 자릿수(4바이트 unsigned big-endian) + ASCII 숫자열. 전부 0이면 한 자리 0.
- 문자 토큰: 표식 2 + Unicode 스칼라(3바이트 big-endian).
- 토큰열 끝: 표식 0. 문자열 접두사가 같으면 짧은 쪽이 먼저다.
- 바이트 비교는 unsigned 사전순. 숫자 문자열을 정수로 변환하지 않아 긴 숫자도 오버플로하지 않는다.

예: a2와 A02는 모두 010200006101000000013200이다. 동률은 원문으로 풀지 않고 다음 필드 또는 UUID로 푼다. 운영 저장 시 키 규격 버전과 키 재생성 정책을 함께 관리해야 하며 이번 단계는 열/인덱스/백필을 추가하지 않는다.

## 검증

공유 fixture가 8개 곡의 5개 정렬 × 2개 보기 기대 순서를 명시한다. 한글/영문/기호, 자연수 동률, 가수 동률, null 티어, 녹음 없음, 동일 시각, unsigned UUID 경계를 포함한다.

SongListRulesTests 8개: 공유 순서, 검색/계정/상태 격리와 문자 그대로 일치, 최신 녹음 후보 제외, UUID와 null 순서, 커서 조건 결합과 긴 Unicode 문자열, 입력 경계, 구조화 비교와 바이트 비교 대조, 실제 H2 VARBINARY 순서와 keyset 경계.

SongSortDatabaseChecks는 기존 fixtures/contracts/sorting.json의 독립 기대 순서에 대해 실제 DB ORDER BY와 2개씩 keyset 조회 결과를 비교한다. MySqlIdempotencyTests에서 같은 검사를 실제 MySQL로 실행한다. 테스트 전용 song_sort_probe는 격리된 테스트 DB 안에서만 생성한다.

제작 환경에서는 MySQL 전용 테스트를 건너뛴다. 푸시 후 CI / API contract / Idempotency MySQL 세 workflow의 결과를 확인한다.

## P08-05b 연결 항목

운영 정렬/검색 키 저장과 기존 행 처리, 생성·향후 편집 시 키 갱신, 계정·ACTIVE·q를 공유하는 count/keyset SQL, ACTIVE·SAVED MAX(recorded_at), 5개 정렬과 그룹별 보기, 키 설정 및 GET /songs 응답/OpenAPI, 실제 MySQL 페이지/검색 회귀 검증을 연결한다. 모바일 화면 연결은 P17 범위다.
