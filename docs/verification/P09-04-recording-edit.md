# P09-04 녹음 정보 수정

기준: P09-03b (`318018c2c7a593d0fe0d001c26b8082f8ca76e62`).
근거: 구현계획서 P09-04, 설계서 2.4~2.7·4.2·5·12.4.

## API와 입력 규칙

`PATCH /v1/recordings/{id}`에 일반 정보 수정을 추가한다. Authorization, X-Device-Id,
Idempotency-Key와 양의 base_revision을 사용한다. 인증 계정과 ACTIVE 상태를 확인한다.
다른 계정의 녹음/태그는 404, 이전 revision은 409 REVISION_CONFLICT를 반환한다.
충돌 응답의 current는 녹음 행 잠금을 유지한 상태에서 읽은 현재 메타정보와 태그다.

- 수정 가능: title_snapshot, artist_snapshot, note, key_mode, key_shift, version_code,
  recorded_at, timezone_id, timezone_offset_minutes, condition_code, tag_ids.
- 누락 필드는 유지한다. note null은 빈 문자열, condition_code null은 해제다.
- DRAFT의 제목·가수·키는 null을 허용한다. 키는 둘 다 null 또는 유효한 쌍이어야 한다.
- SAVED의 제목·가수·키는 비울 수 없다. SAVED→DRAFT는 거절한다.
- 버전은 NORMAL/MR/LIVE만 허용하며 null은 거절한다. 곡 및 다른 녹음의 버전은 바꾸지 않는다.
- tag_ids 누락은 유지, []는 해제, null·중복은 거절한다. 다른 계정 태그와 새 보관 태그 연결은 거절한다.
  기존 관계는 삭제 후 재생성하지 않으므로 보관된 태그도 유지 가능하고 과거 name_snapshot도 유지한다.
- 컨디션은 현 DB 계약의 VERY_GOOD/GOOD/NORMAL/BAD를 사용한다. 같은 코드 재선택 시 당시 이름을 유지한다.
  분류 생성·이름 수정·archive API와 사용자별 컨디션 모델 확장은 P09-07 범위다.
- 시각은 UTC Z 표기, 밀리초 이하 3자리, 1000~9999년 범위다. 시간대는 유효한 IANA ID,
  오프셋은 -1080~1080분을 받는다. 기존 생성 계약처럼 기기가 보고한 시간대·오프셋을 보존한다.
- file이 있는 요청은 기존 P09-02 DRAFT→SAVED 검증 경로를 사용한다. 일반 수정으로 파일 명세를 바꾸지 않는다.
- song_id·tier·소유자·원래 기기·revision 직접 지정은 거절한다. 연결/티어는 후속 전용 API 범위다.

일반 수정 응답은 RecordingEdited다. 메타정보, tag_ids, 태그 당시 이름, 컨디션 당시 이름을 반환하고
같은 payload를 change_log에 남긴다. 파일 명세와 클라우드 상태는 이 응답에 추가하지 않는다.
기존 SAVED 전환 응답 RecordingSaved와 DRAFT 생성 응답 RecordingDraft는 유지한다.

## 트랜잭션과 시각 보정

기존 mutation receipt → USER_SYNC → recording 잠금 순서를 유지한다. 메타정보, 제목 정렬 키,
태그 관계, revision, 시각 이력, 작업 등록, change_log와 change_seq, 멱등 응답은 함께 확정/롤백한다.
태그 이름 수정·archive의 후속 작성자도 USER_SYNC 잠금을 공유해야 한다.

V14는 recording_time_correction을 추가한다. 실제 시각 또는 시간대/오프셋이 달라진 경우에만
이전·변경 값, 새 recording revision, 수정 기기와 서버 시각을 기록한다.
같은 값 재전송이나 동일 멱등 키 재시도는 이력과 작업을 중복 생성하지 않는다.

연결된 SAVED 녹음의 recorded_at이 변경되면 기존 JobQueue에 POLICY_RECALCULATE를 등록한다.
aggregate_id는 song_id이며 payload에는 song_id/recording_id/recording_revision/reason만 둔다.
시간대 표시만 바뀌거나 미연결/DRAFT이면 선정 재계산 작업을 만들지 않는다.
실제 선정 계산 및 작업 소비는 P11에서 연결한다. 이번 단계에서 서버 파일을 전송하거나 삭제하지 않는다.
목록 change_seq가 증가하므로 이전 녹음/곡 목록 커서는 새 첫 페이지 조회를 요구한다.

V14는 기존 녹음과 파일을 변경하지 않는다. 서버 시작 시 Flyway가 적용한다.
이력의 계정·녹음·기기 FK를 두므로 후속 영구 삭제에서는 이력 제거 순서도 포함해야 한다.

## 검증

- HTTP: DRAFT 부분 수정/null, SAVED 필수값·역전환 차단, 잘못된 값, 인증·계정 격리,
  다른 계정 태그, 비활성 녹음, 정렬 키 반영/이전 커서 만료, revision 충돌의 현재 메타정보.
- H2와 전체 Flyway MySQL이 공유하는 시나리오: 저장 파일 명세·연결 곡 불변,
  시각 이력/정책 작업/태그와 함께 수정, change_log 강제 실패의 전체 롤백, 동일 키 재시도,
  보관 태그 유지·이름 스냅샷 유지·해제 후 재선택 차단, 동일 revision 동시 수정의 단일 승자.
- 일반 수정 경로에는 파일 저장소·용량·업로드 의존성이 없다.
- API 계약에 일반 수정 요청/응답 및 경계 사례를 추가한다.
- CI의 단계별 Flyway 검증 버전을 14로 확장한다. MySQL 테스트는 실제 Actions 결과로 확인한다.

모바일 편집 UI, 상세 GET API, 티어/재연결, 분류 관리, 정책 작업 실행기는 이번 범위가 아니다.
