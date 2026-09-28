# P09-06 녹음 재연결

기준: P09-05 `2addb00cec2d3774db353de455d0248cf71ed33d`.
근거: 구현계획서 P09-06, 설계서 4.2·5·9·11의 관계/대표/재연결 규칙.

## API

`PATCH /v1/recordings/{id}/song`

```json
{"base_revision": 2, "song_id": "11111111-0000-4000-8000-000000000002"}
```

song_id는 필수이며 null은 연결 해제다. 인증 계정의 ACTIVE 녹음(DRAFT/SAVED)에 허용한다.
연결 대상은 같은 계정의 ACTIVE 곡이어야 한다. 다른 계정/없는 녹음·곡은 404,
비활성 녹음/대상 곡은 409, 잘못된 입력은 400, revision 충돌은 현재 스냅샷과 함께 409다.
Authorization, X-Device-Id, Idempotency-Key를 사용하며 응답은 RecordingEdited다.

실제 관계가 바뀌면 recording revision과 link_revision을 각각 1 증가시킨다.
같은 관계를 새 op_id로 다시 제출하면 recording revision은 증가하지만 link_revision,
대표 지정, 선정 결과, 작업 수는 유지한다. 동일 op_id 재시도는 기존 응답을 돌려준다.
link_revision 최대값에서는 실제 연결 변경을 거절한다. 이 값은 후속 휴지통 복원의
‘분리 이후 사용자가 연결을 바꿨는가’ 판정에 사용한다.

## 잠금과 FK 처리

receipt → USER_SYNC → 관련 Song(UUID 문자열 정렬) → Recording → 이전 SongSelection → Job 순서다.
계정 잠금 안에서 이전 연결을 먼저 확인하고 두 곡을 미리 잠근다. RevisionChanges.lock은
호출자의 트랜잭션에서 행을 잠그기만 하며 revision을 바꾸지 않는다.

1. 이전 Song의 대표가 이 녹음일 때만 대표 FK를 해제하고 Song revision과 SONG 변경 로그를 남긴다.
2. 이전 song_cloud_selection의 representative/latest/lowest 중 이 녹음을 가리키는 참조만 해제한다.
   다른 녹음 참조는 유지한다. 실제 해제 시 selection_revision을 증가시킨다.
3. composite FK 참조를 해제한 뒤 recording.song_id/link_revision을 갱신한다.
4. null을 제외한 이전·새 곡 각각 POLICY_RECALCULATE를 등록한다.
   JobQueue.enqueueAll은 dedupe 해시 순으로 등록하여 두 작업의 잠금 순서 역전을 막는다.
5. 녹음 변경 로그·change_seq·멱등 응답을 함께 확정한다.

어느 단계든 실패하면 대표·선정 참조·연결·revision·작업·변경 로그·receipt 전부 롤백한다.
원래 녹음의 제목·가수·키·버전·메모·시각·분류·티어·기기·파일 명세/서버 파일은 바꾸지 않는다.
새 곡의 제목이나 버전으로 녹음을 덮어쓰거나 새 곡의 대표를 자동 지정하지 않는다.
파일 삭제/전송, 고정 해제, ORPHAN_KEEP 해제는 이 경로에서 수행하지 않는다.
실제 선정 재계산과 보관/정리 판단은 P11의 정책 작업 소비 단계에서 처리한다.

## 검증

- H2/전체 Flyway MySQL 공통: 이전 곡 ID가 새 곡 ID보다 큰 순서의 재연결,
  대표와 세 선정 FK 동시 해제, 두 곡 작업, SONG/RECORDING 로그,
  파일·당시 입력·새 곡 불변, 강제 change_log 실패의 전체 롤백, 동일 키 재시도,
  같은 연결 재제출, 명시적 해제, 미연결에서 재연결, 동시 요청의 단일 승자.
- HTTP: DRAFT 불완전 입력 유지, 계정 격리, 비활성/잘못된 입력/버전 상한,
  목록 곡 필터 반영과 이전 커서 만료, 인증 실패 및 revision 충돌 응답.
- 기존 revision/job/곡/녹음 테스트도 전체 실행한다.
- API 계약: 구현 상태, RecordingEdited 응답, SongLinkPatch 경계 사례.

새 DB 마이그레이션은 없다. 모바일 연결 선택기 및 정책 작업 실행기는 후속 단계다.
MySQL 전용 테스트의 실행 결과는 GitHub Actions에서 확인한다.
