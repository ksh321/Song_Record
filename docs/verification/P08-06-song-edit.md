# P08-06 곡 편집 API

## 범위

PATCH /v1/songs/{id}를 구현한다. 곡명·가수·note·대표 키·버전·곡 티어만 수정할 수 있다. GET 상세, 대표 녹음 지정(P08-07), 모바일 편집 화면(P17)은 이번 범위가 아니다. 대표 키와 대표 녹음은 별개다.

## 요청 계약

Authorization, X-Device-Id, Idempotency-Key와 base_revision이 필요하다. 계정은 인증 세션에서 결정한다. 허용하지 않은 필드는 400 VALIDATION_FAILED로 거절한다. source_type, tj_number, source_token, 언어, id, user_id, representative_recording_id는 수정할 수 없다.

- title/artist: 누락=유지, null 불가. 계약 공백 trim 후 1~200 Unicode code points.
- note: 누락=유지, null=빈 문자열. 줄바꿈을 LF로 통일한 뒤 최대 2000 code points. 이모지 하나를 UTF-16 길이 2로 세지 않는다.
- version_code: NORMAL/MR/LIVE, null 불가.
- tier: S/A/B/C/D, null=미정.
- representative_key_mode: ORIGINAL/MALE/FEMALE 또는 null.
- representative_key_shift: -12~12 정수 또는 null.

대표 키는 누락된 필드를 기존 값으로 채운 최종 상태를 검증한다. 두 필드가 함께 null이거나 모두 유효해야 하며 ORIGINAL은 shift=0이다. 예를 들어 FEMALE/-2에서 shift만 3으로 바꾸는 것은 가능하다. mode만 ORIGINAL로 바꾸고 shift=-2를 남기는 것은 불가능하다. 해제하려면 두 필드를 null로 보낸다.

성공은 200 Song이며 representative_key_mode/shift를 생성·목록·수정 응답에 함께 노출한다. 새로 만든 응답의 null도 생략하지 않는다. 다만 이전 단계에서 저장한 생성 영수증은 최초 응답 그대로 재전송하므로 대표 키 필드가 없을 수 있다. 이 호환성을 위해 Song 스키마의 신규 대표 키 필드는 선택 필드로 둔다. Cache-Control은 no-store다. REVISION_CONFLICT의 current도 song_tier 같은 DB 컬럼명이 아닌 tier를 사용하는 Song 응답 형태로 변환한다.

## 트랜잭션·충돌·재시도

IdempotentMutations의 영수증 예약 → AccountChanges의 계정 sync 행 잠금 → RevisionChanges의 계정+곡 행 잠금 → base_revision 비교 → 필드 수정·파생 키 교체 → revision+1 → 변경 로그·change_seq → 최종 영수증 순서로 같은 트랜잭션에서 처리한다.

같은 base_revision으로 경쟁한 새 요청 둘은 하나만 성공하고 나머지는 409 REVISION_CONFLICT와 최신 값/버전을 받는다. 타인 또는 없는 곡은 404 RESOURCE_NOT_FOUND로 구분 없이 거절한다. 자신의 휴지통 곡은 SONG_RESTORE_REQUIRED, 삭제 대기는 SONG_PURGE_PENDING, PURGED는 RESOURCE_PURGED다. revision 검사가 상태 검사보다 먼저 수행된다.

같은 Idempotency-Key와 같은 원래 요청은 최초 응답을 반환한다. 이후 다른 수정으로 곡 revision이 증가해도 재시도는 최초 결과다. 같은 키의 본문 변경은 IDEMPOTENCY_CONFLICT. 새 요청으로 받아들인 PATCH는 값이 같거나 base_revision만 있어도 revision과 변경 로그를 한 번 증가시킨다. 재전송 때문에 다시 증가하지는 않는다.

제목/가수 수정은 같은 트랜잭션 안에서 해당 계정의 song_query_key를 DELETE+INSERT로 교체한다. 읽기는 커밋 전 값 또는 커밋 후 값을 보며 중간의 키 누락을 보지 않는다. 파생 키나 변경 로그 저장이 실패하면 곡 값, 키, revision, change_seq, 영수증이 함께 롤백한다. 같은 요청 키로 재시도할 수 있다.

note만 바꾸는 경우에도 계정 change_seq가 증가하므로 기존 목록 cursor는 LIST_CURSOR_EXPIRED가 된다. 이전 페이지를 계속 이어 붙여 수정 누락을 만드는 대신 목록을 처음부터 다시 읽는다.

## 기존 정보 보존

SongSource 원본, 모든 Recording의 제목/가수 snapshot·버전·키·티어·메모·revision, 곡의 대표 녹음 ID는 바꾸지 않는다. 새 녹음의 기본값 선택과 기존 녹음의 저장값은 별개다. 곡 버전 변경이 과거 녹음에 전파되지 않는다. 이후 연결된 플레이리스트 표시는 Song을 읽는 단계에서 반영하며 이번 단계에 모바일 화면 동기화 완료를 주장하지 않는다.

V10/V11 등 기존 migration은 변경하지 않는다. SongQueryKeys에 replace를 추가했으며 기존 insert/인코딩 의미와 V11 backfill은 그대로다. 신규 DB migration이나 별도 환경변수 설정은 없다.

## 검증

SongEditingTests 7개: 모든 필드/2000자 이모지/원본·녹음 보존, 누락·null·대표 키 병합 검증, 멱등 재시도와 충돌 응답, 불변 필드·숫자·길이 경계, 인증·소유권·상태, 키 및 로그 실패 롤백과 동일 키 재시도, 목록 커서 무효화·빈 수정의 revision 규칙.

MySqlIdempotencyTests 1개 추가: 실제 V2/V10 테이블에서 동시 수정 승자 1개, 멱등 재시도, 파생 키 일치, MySQL CHAR_LENGTH(note)=2000, 키 CHECK/변경 로그 trigger 오류의 전체 롤백과 재시도, 과거 녹음 보존을 검사한다.

OpenAPI와 공통 schema fixture에 대표 키 PATCH/응답 계약을 추가했다. H2의 note 테스트 열은 UTF-16 길이 차이를 피하도록 넓히고, 실제 MySQL 2000 code point 제약은 MySQL 전용 검사로 별도 확인한다.

제작 환경에서 MySQL 전용 검사는 건너뛰므로 푸시 후 CI / API contract / Idempotency MySQL을 모두 확인해야 한다. 휴대폰 재설치나 화면 수동 검사는 이번 단계에 필요하지 않다.
