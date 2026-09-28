# P08-04 수동 곡 생성

## API 계약

POST /v1/songs에 source_type=MANUAL 경로를 연결한다. 기존 인증, 계정 소유권, 멱등 영수증, 계정 잠금, deletion_ledger, 변경 로그 트랜잭션을 공유한다.

필수 값은 id(UUID), source_type=MANUAL, manual_reason=TJ_NOT_FOUND, title, artist다. 곡명·가수는 공통 정규화 후 1~200 Unicode code points. 번호(tj_number)는 null을 보내도 거절하며 source_token도 허용하지 않는다. TJ 요청에 manual_reason을 넣는 것도 거절한다. version_code 기본 NORMAL, note 기본 빈 문자열, tier 기본 null은 TJ와 같다.

manual_reason은 사용자가 검색 결과에서 원하는 곡을 찾지 못했음을 확인한 사유다. 전 세계 TJ 목록에 곡이 없다는 서버의 증명이 아니다. 사유를 song 테이블에 새 열로 보관하지 않는다. 생성 요청 검증에 사용하며 기존 멱등 요청 해시에 반영된다.

MANUAL은 tj_number/reserved_tj_number=null, song_source 행 없음. 같은 곡명·가수라도 UUID가 다르면 각각 201로 생성한다. 같은 UUID를 다른 요청 키로 보내면 기존 ACTIVE 곡을 200으로 돌려주며 편집값을 덮어쓰지 않는다. 같은 요청 키는 최초 응답을 그대로 재전송하며 요청 내용 변경은 IDEMPOTENCY_CONFLICT다.

같은 UUID의 TJ/MANUAL 변경은 SONG_ID_CONFLICT. 휴지통은 SONG_RESTORE_REQUIRED, 삭제 대기는 SONG_PURGE_PENDING, 삭제 표식은 RESOURCE_PURGED. 소유자는 요청 본문이 아닌 인증 세션에서 결정한다.

## 검색 장애와 트랜잭션

TJ 후보 검증 실패를 catch하여 MANUAL로 전환하지 않는다. 검증기가 503을 반환하면 요청 전체가 실패하며 곡·영수증·변경 기록을 남기지 않는다. 이미 검색 결과 확인을 마친 MANUAL 입력은 후보 검증기를 호출하지 않고 생성할 수 있다.

신규 곡 INSERT, change_seq 증가, change_log INSERT, 최종 영수증은 같은 트랜잭션이다. 변경 로그 INSERT 실패 시 앞선 곡 저장도 롤백한다. MySQL의 (user_id, reserved_tj_number) 유일 제약은 null 번호의 MANUAL 여러 행을 허용한다.

## 검증

SongCreationTests에 6개 추가: 수동 생성/재시도/멱등 충돌, 동명 다른 UUID와 기존 값 보존, 필수 값/번호/출처 혼합 거절, 검색 장애 자동 전환 차단, 유형 변경/삭제 상태 차단, 변경 로그 실패 전체 롤백.

MySqlIdempotencyTests에 1개 추가: 실제 V2 song/song_source와 V6 deletion_ledger DDL로 null 번호 여러 행, source 생략, 재시도, 중복 UUID, trigger가 발생시킨 변경 로그 오류의 원자적 롤백을 검증한다. 제작 환경에는 MySQL이 없어 해당 테스트는 건너뛰며 Idempotency MySQL Actions에서 실행해야 한다.

기존 DB 스키마로 구현하여 마이그레이션은 없다. 이번 단계는 서버 API이며 앱 직접 입력 화면·오프라인 보존·검색 결과에 따른 진입 UX는 후속 모바일 단계다. 휴대폰 재설치나 수동 조작은 필요하지 않다.
