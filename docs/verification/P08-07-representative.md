# P08-07 대표 녹음 지정·해제 API

## 계약

PUT /v1/songs/{id}/representative. Authorization, X-Device-Id, Idempotency-Key가 필요하며 계정은 인증 세션에서 결정한다.

```json
{"base_revision": 1, "recording_id": "00000000-0000-4000-8000-000000000001"}
```

recording_id를 명시적 null로 보내면 해제한다. 두 필드 모두 필수이며 추가 필드, 잘못된 UUID, 1 미만·소수·long 범위 초과 revision은 400 VALIDATION_FAILED다. 곡 일반 PATCH로 대표 녹음 ID를 우회 수정할 수 없다.

성공 200 Song, Cache-Control: no-store. 생성·목록·수정·대표 지정 응답에 representative_recording_id를 UUID 또는 null로 포함한다. 이전 멱등 영수증은 원래 응답 그대로 재전송하므로 새 필드가 없을 수 있으며 Song 스키마는 호환성을 위해 이 필드를 선택으로 둔다.

## 권한과 상태

- 타인/없는 곡 또는 타인/없는 녹음: 404 RESOURCE_NOT_FOUND. 타인 자료의 존재를 노출하지 않는다.
- 본인 녹음이지만 다른 곡, 미연결, DRAFT 또는 ACTIVE가 아닌 상태: 409 REPRESENTATIVE_NOT_ELIGIBLE.
- ACTIVE 곡만 지정·해제할 수 있다. TRASHED는 SONG_RESTORE_REQUIRED, PURGE_PENDING은 SONG_PURGE_PENDING, PURGED는 RESOURCE_PURGED.
- base_revision이 다르면 409 REVISION_CONFLICT. current_revision과 Song 형태의 current를 반환한다. revision 비교가 상태 검사보다 먼저다.
- 파일의 로컬 존재, 클라우드 업로드 상태는 자격 조건이 아니다. 같은 소유자·같은 곡·ACTIVE·SAVED를 만족해야 한다.

대표 녹음 포인터만 수정하며 곡의 대표 키·버전·티어와 녹음 snapshot·키·버전·티어·revision은 변경하지 않는다. 검색 파생 키도 다시 만들지 않는다.

## 트랜잭션과 경쟁 요청

멱등 영수증 예약 → 계정 USER_SYNC 잠금 → SONG 행 잠금과 revision 검사 → 대상 RECORDING 행 FOR UPDATE 잠금과 자격 검사 → 대표 포인터 변경 → Song revision+1 → change_log와 change_seq → 최종 영수증을 하나의 트랜잭션으로 처리한다. 해제는 대상 녹음 검사가 필요 없다.

녹음 검증은 잠금 없는 사전 조회가 아니다. 검증한 상태가 커밋 전에 바뀌지 않도록 대상 행을 잠근다. 명시적 잠금 순서는 USER_SYNC → SONG → RECORDING이다. V2의 실제 (user_id,id,representative_recording_id) 복합 FK도 같은 소유자·같은 곡을 DB 수준에서 보장한다. FK만으로 ACTIVE·SAVED까지 보장되지는 않아 서비스 검증이 필요하다.

같은 base_revision으로 지정/해제가 경쟁하면 하나만 성공한다. 같은 멱등 키·본문은 원래 응답을 반환한다. 지정 후 해제하고 옛 지정 요청을 재전송해도 다시 지정하지 않는다. 같은 키의 본문 변경은 IDEMPOTENCY_CONFLICT다. 동일 상태를 새 요청 키로 요청하면 revision과 로그는 한 번 증가한다. 목록 커서는 change_seq 변경에 따라 무효화된다.

변경 로그 저장 실패 시 포인터·revision·change_seq·영수증이 함께 롤백하며 같은 키로 재시도할 수 있다.

향후 녹음 삭제·미연결·다른 곡 재연결 구현에서도 같은 계정/곡/녹음 잠금 규칙을 지키고 기존 대표 포인터를 같은 트랜잭션에서 해제해야 한다. 삭제 후 복원 시 자동 대표 재지정은 하지 않는다. 이번 단계는 그 후속 API를 구현한 것이 아니다.

## 검증과 적용

SongRepresentativeTests 6개: 지정/교체/해제와 녹음·검색 키 보존, 해제 후 옛 요청 재전송·충돌 current, 계정/곡/상태별 거절, 인증·곡 소유권·곡 상태, 요청 경계·일반 PATCH 우회 차단, 로그 실패 전체 롤백과 재시도.

MySqlIdempotencyTests에 실제 V2 테이블과 대표 녹음 복합 FK를 설치하는 검사 1개 추가: 지정/해제 경쟁, 승자 재전송, 교차 곡 FK 차단, 변경 로그 trigger 실패 롤백/동일 키 재시도, 녹음 보존, 해제 후 휴지통 녹음 지정 차단. 기존 Idempotency MySQL workflow에서 함께 실행한다.

새 migration, 새 환경변수, 모바일 설치/수동 검사는 필요 없다. 제작 환경에서는 MySQL 전용 검사를 실행하지 못하므로 푸시 후 CI / API contract / Idempotency MySQL 세 workflow를 확인한다.
