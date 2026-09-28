# P09-01 녹음 DRAFT 생성

## 구현 범위

POST /v1/recordings는 P09-01에서 DRAFT 생성만 구현한다. 제목·가수·키가 미정이어도 녹음 시각과 입력 중 정보를 보존한다. 앱 연결은 후속 단계이며 파일 업로드, 완료 파일 명세, SAVED 전환, 태그/컨디션/티어 변경은 아직 지원하지 않는다. 지원하지 않는 필드를 전달하면 400으로 거절하고 조용히 버리지 않는다.

기존 미래 계약 RecordingCreate/Recording은 유지하고 실제 구현 범위를 RecordingDraftCreate/RecordingDraft로 명시한다. 앱 연동 전 P09 후속 단계에서 계약을 확장한다.

## 요청

Authorization, X-Device-Id, Idempotency-Key가 필수다. user_id와 origin_device_id는 인증된 세션에서 정하며 본문으로 지정할 수 없다.

```json
{"id":"00000000-0000-4000-8000-000000000001","metadata_state":"DRAFT","recorded_at":"2026-09-28T07:00:00.123Z","timezone_id":"Asia/Seoul","timezone_offset_minutes":540}
```

- id, metadata_state=DRAFT, recorded_at, timezone_id, timezone_offset_minutes는 필수다.
- title_snapshot/artist_snapshot: null·누락·공백만 있으면 null. 입력이 있으면 계약 공백 정리 후 최대 200 Unicode code points.
- version_code: 누락 시 NORMAL, 명시적 null은 거절. NORMAL/MR/LIVE만 허용한다.
- key_mode/key_shift: 둘 다 null/누락 또는 유효한 쌍. ORIGINAL은 0, MALE/FEMALE은 -12~12 정수. 단독 지정은 거절한다.
- note: null/누락은 빈 문자열, 줄바꿈 LF 정규화, 최대 2000 Unicode code points.
- recorded_at: UTC Z 표기, 최대 밀리초 정밀도, 실제 존재하는 일시, MySQL DATETIME 범위인 1000~9999년.
- timezone_id: 서버에 알려진 IANA ID(UTC 포함), 최대 64자. offset은 -1080~1080 정수로 보존한다. 시간대 규칙 변경으로 원래 기록이 변하지 않도록 캡처한 오프셋을 저장하며 현재 시간대 규칙으로 덮어쓰지 않는다.
- song_id: null/누락이면 미연결. 지정 시 같은 계정 ACTIVE 곡만 허용한다. 없는 곡/타인 곡은 404 RESOURCE_NOT_FOUND, 비활성 곡은 409 SONG_NOT_ACTIVE.

곡과 연결해도 입력된 snapshot·버전을 곡 기본값으로 덮어쓰지 않는다. 기본값 선택은 앱 입력 단계 책임이다.

## 응답과 재시도

201 RecordingDraft는 origin_device_id, revision=1, link_revision=1과 저장된 필드, 상태 및 updated_at을 포함한다. Cache-Control은 no-store다. 이 성공은 음성 파일의 클라우드 저장 완료를 의미하지 않는다. 파일/asset/용량 테이블을 사용하거나 외부 서비스에 접근하지 않는다.

같은 요청 키·본문은 최초 응답을 그대로 재전송한다. 같은 키의 다른 본문은 IDEMPOTENCY_CONFLICT다. 새 키로 같은 UUID를 보내면 기존 ACTIVE DRAFT를 200으로 반환하며 입력을 덮어쓰거나 revision/로그를 증가시키지 않는다. 원본 기기도 처음 생성한 기기로 유지한다.

이미 SAVED인 UUID는 RECORDING_ALREADY_SAVED로 거절하여 초안으로 되돌리지 않는다. TRASHED/PURGE_PENDING/PURGED 및 삭제 원장은 각각 상태 오류로 부활을 차단한다. 다른 계정이 사용하는 UUID는 RECORDING_ID_CONFLICT로 거절하며 내용을 반환하지 않는다. UUID 삭제 표식 검사는 곡 연결 검사보다 먼저 수행한다.

## 트랜잭션과 잠금

IdempotentMutations가 영수증을 예약하고 CreationGuard가 USER_SYNC → RECORDING 잠금과 삭제 원장 검사를 수행한다. 새 녹음은 Recording 행·change_log·계정 change_seq·최종 영수증을 같은 트랜잭션으로 저장한다. 중간 실패 시 모두 롤백하여 같은 요청 키로 재시도할 수 있다.

곡 상태 조회는 이미 보유한 계정 USER_SYNC 잠금으로 참여하는 곡 수명 변경과 직렬화된다. RECORDING 다음에 SONG 잠금을 획득하지 않는다. 연결 소유권은 실제 V2 복합 FK도 보장한다. 향후 곡 삭제/녹음 재연결 구현 역시 같은 계정 잠금 규칙을 따라야 한다.

JSON 중복 키와 후행 토큰은 CanonicalRequest로 검사하되 필드 타입 검사는 원본 JSON에서 수행한다. 정규화가 540을 지수 표기로 바꾸더라도 정상 정수 오프셋을 소수 입력으로 오판하지 않는다. 멱등 해시는 기존 정규화 규칙을 그대로 사용한다.

## 검증

RecordingDraftTests 6개: 미완성 정보와 원본 기기 보존, 멱등/UUID 중복/덮어쓰기 방지, 시간·키·버전·문자 수·지원 필드 경계, 곡 소유권/상태와 snapshot 보존, 인증·수명·삭제 원장, 로그 저장 실패 롤백 및 같은 키 재시도.

MySqlIdempotencyTests에 실제 V2/V6 기반 동시 UUID 생성 검증 추가. 서로 다른 요청 키로 같은 UUID를 생성해도 행/변경 로그는 하나, 201/200 응답, 영수증 재전송, 실제 nullable 필드/기기 FK, 로그 trigger 실패 전체 롤백을 확인한다. 파일/용량 테이블 없이 실행한다.

OpenAPI 구현 경로 검사, DRAFT 요청/응답 schema fixture와 전체 서버 test bootJar도 검증한다. 제작 환경에서 MySQL 전용 검사는 건너뛰며 푸시 후 Idempotency MySQL에서 실행한다.

새 migration이나 환경변수는 없다. CI / API contract / Idempotency MySQL 세 workflow 확인. 휴대폰 재설치/수동 화면 테스트는 필요 없다. 다음 단계 P09-02에서 완료 파일 명세와 SAVED 전환을 구현한다.
