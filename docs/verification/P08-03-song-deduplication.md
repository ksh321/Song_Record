# P08-03 TJ 번호 중복과 ID 매핑 검증

## 범위

P08-02 SongCreation에 연결된 중복 처리를 별도 단계의 완료 조건으로 검증한다. 운영 코드/마이그레이션/모바일 변경 없이 HTTP·DB 회귀 테스트를 추가한다. 동시 등록 MySQL 검사는 기존 Idempotency MySQL workflow에서 실행한다.

## 식별자 계약

- op_id는 요청 재시도의 식별자다. 서로 다른 op_id여도 같은 곡일 수 있다.
- 요청 song UUID는 앱이 생성한 자료 식별자다. 다른 기기에서 같은 TJ 곡에 서로 다른 UUID를 부여할 수 있다.
- TJ 번호의 중복 범위는 계정이다. 같은 계정의 같은 예약 번호는 하나의 곡이며 다른 계정은 독립적으로 등록 가능하다.
- canonical_song_id는 실제 서버 곡의 UUID다. 응답 Song.id와 같으며 이미 존재하는 번호면 요청 UUID와 다를 수 있다.

새 자료는 201 created=true, 중복은 200 created=false다. 기존 곡의 title/artist/note/version/tier/대표 키/revision/updated_at을 덮어쓰지 않는다. 중복 요청용 영수증은 생기지만 곡/출처/변경 로그/계정 change_seq는 추가되지 않는다. 같은 요청 키의 재시도는 해당 요청에 저장된 원래 응답을 재전송한다.

서버가 요청 UUID를 영구 별칭 테이블에 저장하는 기능은 없다. P10 앱 동기화에서 canonical_song_id를 기준으로 대기 녹음/관계의 로컬 ID를 실제 서버 ID로 재매핑해야 한다. 이번 단계에서 모바일 ID 재매핑 완료를 주장하지 않는다.

## 동시성

각 요청은 자기 영수증을 예약한 뒤 CreationGuard의 계정 sync 행 잠금을 획득한다. 동일 계정 생성은 이 지점에서 직렬화된다. 앞 요청이 커밋한 뒤 다음 요청은 이미 존재하는 reserved_tj_number를 조회해 기존 곡을 반환한다. uq_song_owner_reserved_tj 유일 제약은 서비스를 우회한 INSERT도 중복 저장하지 못하게 하는 추가 방어다.

정상 서비스 경로는 DB 중복 예외를 일부러 발생시키기보다 계정 잠금 아래 기존 번호를 확인한다. 다른 쓰기 경로도 공통 계정 잠금 규칙에 참여해야 한다. arbitrary SQL의 충돌을 모두 canonical 응답으로 바꾸는 것은 아니다. 실제 유일 제약 위반 시 현재 서비스는 일반 SONG_ID_CONFLICT로 거절한다.

## 상태 경계

- ACTIVE: 기존 canonical 곡 반환.
- TRASHED: SONG_RESTORE_REQUIRED. 휴지통에서 번호 예약을 유지한다.
- PURGE_PENDING: SONG_PURGE_PENDING. 완료를 기다린다.
- PURGED: 새 UUID로 번호 재등록 가능. 이전 UUID의 deletion_ledger는 계속 재생성을 막는다.
- 요청 UUID의 영구 삭제 표식은 번호 매핑보다 먼저 확인한다.
- 같은 UUID에 다른 TJ 번호를 넣으면 SONG_ID_CONFLICT.
- 제목/가수가 같아도 번호가 다르면 별개의 곡.

## 테스트

SongCreationTests에 5개 추가: 모든 기존 편집값/최신 revision/수정 시각 보존, 예약 상태 및 PURGED 뒤 새 UUID 재등록/이전 UUID 차단, 동일 UUID 번호 변경 거절, 동명 다른 번호 분리, 다른 계정 번호 분리.

MySqlIdempotencyTests에 1개 추가: 실제 V2 song/song_source DDL 및 source INSERT trigger로 서로 다른 UUID/op_id의 요청 둘을 두 DB 연결에서 경쟁시킨다. 한쪽은 201, 다른 쪽은 200이고 canonical ID는 같아야 한다. 곡/출처/변경 로그는 각 1개, 영수증은 2개이며 재시도 응답도 동일해야 한다. 후속 중복 요청의 편집값 보존과 직접 INSERT의 유일 제약 위반까지 검사한다. 최초 승자가 누구인지는 정하지 않는다.

테스트의 직접 UPDATE는 기존 사용자 편집/삭제 완료 상태를 준비하는 fixture다. 실제 수정·삭제 업무는 공통 변경 기록 트랜잭션을 따라야 한다. MySQL 전용 검사는 제작 환경에서 실행하지 못하므로 Actions 통과를 별도로 확인한다.
