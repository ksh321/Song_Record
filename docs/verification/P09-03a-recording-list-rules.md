# P09-03a 녹음 목록 필터·정렬 계약

## 현재 범위

P09-02 커밋 25eaf26a10aa4f9d6b7abf0f1ebbf4f6554b4860의 CI / API contract / Idempotency MySQL 성공을 확인하고 진행한다. 같은 커밋의 취소된 CI 실행 이후 성공한 실행이 존재한다.

이번 작업은 P09-03의 첫 하위 작업으로 RecordingListRules와 단위 검증, OpenAPI 예정 query 계약을 추가한다. GET /v1/recordings는 아직 planned다. P09-03 전체 완료 또는 앱 녹음 목록 연결 완료로 표시하지 않는다.

P09-03b에서 SQL 조회와 제목 정렬 키 저장·backfill, 실제 DB/HTTP/커서 페이지 통합을 연결한다. Java에서 전체 데이터를 가져온 다음 필터링/정렬하는 방식으로 운영 API를 구현하지 않는다. 이번 메모리 판정기는 다음 SQL 결과를 검증할 기준이다.

## 필터 계약

인증 계정의 ACTIVE Recording만 대상이며 곡/녹음 제목 snapshot과 파일 상태는 별개다. 기본은 DRAFT·SAVED 모두 포함한다. metadata_state로 입력 대기/저장 완료를 구분할 수 있다. API 호출 화면은 목적에 따라 SAVED를 명시할 수 있다.

| 매개변수 | 의미 |
|---|---|
| from / to | UTC from 포함, to 제외. 같은 경계·역전은 거절. 최대 밀리초 및 MySQL 날짜 범위 |
| song_id | 소문자 정규 UUID 또는 UNLINKED. 누락하면 전체 |
| key_mode / key_shift | 모드와 -12~12 반음. 각각 독립 조건 |
| version_code | NORMAL/MR/LIVE. 곡 버전이 아니라 녹음 버전 |
| tier | S/A/B/C/D/NONE. NONE은 미정, ALL/누락은 전체 |
| condition_code | VERY_GOOD/GOOD/NORMAL/BAD/NONE. NONE은 미지정, ALL/누락은 전체 |
| tag_ids | 쉼표로 구분한 UUID, 모두 일치(AND). 최대 20개 입력, 정렬·중복 제거 |
| server_file | PRESENT/ABSENT. ALL/누락이면 파일 없는 정보도 유지 |
| metadata_state | DRAFT/SAVED. ALL/누락이면 전체 |
| limit | 기본 50, 1~100 |
| cursor | 공통 불투명 커서 |

서로 다른 필터는 AND로 결합한다. 모순된 조건은 결과 없음이며 다른 계정이나 파일 없는 정보를 임의로 보충하지 않는다. server_file은 서버의 실제 보관 메타정보를 별도로 전달받는다. local_file 등 서버가 판단할 수 없는 매개변수는 거절한다. 업로드 대기 상태만으로 PRESENT라고 추정하지 않는다.

알 수 없는 매개변수, 같은 이름 반복, 빈 값, 잘못된 enum/UUID/기간/숫자 및 범위 초과는 400 VALIDATION_ERROR다. URI 입력 크기를 제한하기 위해 태그 필터 입력 수는 20개로 정한다. 이는 녹음 자체의 태그 보유 개수 제한이 아니다.

## 네 가지 정렬

- RECORDED_DESC: recorded_at 최신순(기본).
- RECORDED_ASC: recorded_at 오래된순.
- TITLE: 녹음 title_snapshot의 공통 자연 정렬. 곡10보다 곡2가 먼저, 빈 제목/null은 마지막. 연결 Song.title 변경이 과거 녹음 정렬을 바꾸지 않는다.
- TIER: S→A→B→C→D→미정, 같은 티어는 recorded_at 최신순.

모든 최종 동률은 unsigned UUID 오름차순이다. 기존 DomainOrdering의 한국어/문자 그룹·정규화·숫자 정렬을 그대로 사용한다. SQL 어댑터에서도 같은 byte key와 UUID 순서를 사용해야 한다.

## 커서 결합

조회 종류 recordings, 정렬, 규칙 버전, 정규화된 전체 필터, limit를 PageCursor.Query에 전달한다. 기존 공통 PageCursor가 인증 계정 및 조회 조건에 암호화 커서를 결합한다.

태그 순서·중복, ALL/누락, 동일 UTC 시각의 .000 표현은 같은 조건으로 정규화한다. 필터/정렬/limit/계정이 달라지면 예전 커서를 사용할 수 없다. recorded_at·제목·티어별 튜플과 비교기가 SQL keyset 페이지 경계를 정의한다.

계정 change_seq 변경·만료 시 LIST_CURSOR_EXPIRED를 처리하는 기존 KeysetPages와의 실제 연결은 P09-03b다. 기간 필터의 UTC 변환은 앱에서 사용자 시간대를 기준으로 수행한다.

## 검증

RecordingListRulesTests 7개: 파일 없는 DRAFT/SAVED 기본 포함과 계정/휴지통 제외, 복합 필터·반개구간·태그 AND, 미정/미지정과 파일 존재 분리, 네 정렬과 빈 제목/최신순/UUID 동률, 튜플 비교와 unsigned UUID, 필터 정규화·커서 조건/계정 결합, 입력 경계/중복/미지원 매개변수.

이번 단계는 DB 스키마와 런타임 엔드포인트를 바꾸지 않는다. 새 MySQL 전용 검사는 없고 기존 MySQL 검사들을 회귀 확인한다. 로컬 test bootJar 및 API 계약 검사 후 푸시하여 CI / API contract / Idempotency MySQL을 확인한다. 휴대폰 조작은 필요 없다.
