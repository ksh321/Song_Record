# P09-02 SAVED 전환

## 범위

PATCH /v1/recordings/{id}의 DRAFT→SAVED 전환을 구현한다. 기존 POST는 DRAFT 전용이다. 일반 필드 편집은 P09-04, 파일 업로드/실제 서버 바이트 검증은 후속 단계다. 구현된 요청·응답은 RecordingSave / RecordingSaved, 파일은 CompletedRecordingFile 스키마로 명시한다. 기존 미래용 RecordingPatch/FileSpecification 스키마는 이 API의 현재 입력으로 사용하지 않는다.

## 요청과 병합

인증·기기·Idempotency-Key와 base_revision, metadata_state=SAVED, file이 필요하다. title_snapshot, artist_snapshot, version_code, key_mode, key_shift, note는 선택 입력이며 누락 시 기존 초안을 유지한다. 병합 후 제목·가수·유효한 버전·키가 모두 있어야 한다. 제목·가수 null/빈 문자열, 잘못된 버전, 키 범위 초과, ORIGINAL의 0 이외 값은 거절한다. note는 null을 빈 문자열로 처리하고 LF 정규화 후 최대 2000 Unicode code points를 허용한다.

file은 다음 7개 필드가 모두 필요하다.

| 필드 | 조건 |
|---|---|
| size_bytes | 정수 1~6,291,456 |
| duration_ms | 정수 1~361,000 |
| sha256 | 소문자 16진수 64자리 |
| codec | AAC_LC |
| sample_rate | 48000 |
| channels | 1 |
| capture_integrity | VALIDATED 또는 RECOVERED |

녹음기 목표 종료는 360초이며 최종 파일의 허용 길이는 설계서/V2와 같이 361초까지다. 앱에서 마무리와 재생 검사를 수행한 파일의 신고 명세를 받는다. 서버는 이번 단계에서 실제 파일을 받거나 디코딩하지 않으므로 신고값 검증을 실제 음성/체크섬 검증 완료로 간주하지 않는다. 서버 파일·클라우드 asset·저장 용량 테이블 없이도 성공한다.

song_id·녹음 시각·원본 기기·티어·태그 등 이번 범위 밖의 필드는 거절한다. 연결 곡의 변경/삭제와 독립적으로 본인 ACTIVE 녹음을 저장 완료할 수 있다. 곡 snapshot을 원래 곡 정보로 덮어쓰지 않는다.

## 저장·충돌·보호

IdempotentMutations → AccountChanges의 계정 잠금 → RevisionChanges의 RECORDING 잠금과 revision 비교 → 필수 입력 병합 검증 → recording_file_spec INSERT → Recording SAVED UPDATE → revision 증가 → 변경 로그·sequence·영수증 순서로 하나의 트랜잭션에서 처리한다. V2 실제 트리거 때문에 파일 명세를 먼저 INSERT해야 한다.

본인 ACTIVE DRAFT만 전환한다. 타인/없는 녹음은 404, 비활성 녹음은 RECORDING_NOT_ACTIVE, 이미 SAVED인 새 요청은 RECORDING_ALREADY_SAVED다. 기존 파일 명세가 있는 초안은 FILE_SPEC_ALREADY_EXISTS로 보호한다. 현재 DRAFT 생성 API는 파일 명세를 받지 않으므로 정상 생성→저장 흐름은 명세가 없는 상태에서 시작한다.

같은 요청 키/본문 재전송은 원래 200 응답을 그대로 반환한다. 새 키로 오래된 base_revision을 보내면 REVISION_CONFLICT다. 같은 키의 다른 본문은 IDEMPOTENCY_CONFLICT다. 같은 revision의 동시 저장 요청은 하나만 성공한다.

SAVED 응답에는 저장된 파일 명세와 최신 revision을 포함하고 Cache-Control=no-store다. origin_device_id, recorded_at, timezone, song_id, link_revision은 유지한다. 저장/파일 명세/로그 중 어느 단계에서 실패해도 모두 롤백되어 같은 키로 재시도할 수 있다. 원래 V2의 트리거가 SAVED→DRAFT 되돌림과 SAVED 파일 명세 변경·삭제를 막는다. 기존 migration은 수정하지 않는다.

## 검증

RecordingSavingTests 5개: 클라우드 없이 상한값 명세 저장·멱등 재시도, 기존 초안 필드 병합·2000자 이모지, 파일 필수/범위/코덱과 지원 필드 검증, 인증·소유권·수명 검사, 로그 실패 시 명세/상태/revision/영수증/sequence 전체 롤백.

MySqlIdempotencyTests에 실제 V2 recording/file_spec 테이블과 4개 원본 트리거를 설치하는 검사 추가: 명세 없는 SAVED 차단, 로그 실패 롤백, 동시 저장 승자 1개, 동일 영수증 재전송, SAVED 되돌림·파일 명세 변경/삭제 차단. RevisionChanges가 읽는 V4 분류 열만 테스트에 보충하며 분류 기능은 호출하지 않는다.

제작 환경에서는 MySQL 전용 테스트를 건너뛴다. 적용 후 로컬 test bootJar, 푸시 후 CI / API contract / Idempotency MySQL을 확인한다. 신규 DB migration/환경변수/휴대폰 재설치는 없다. 앱 화면에서 SAVED API를 호출하는 연결은 후속 작업이다.
