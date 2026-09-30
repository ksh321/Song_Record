# P10-05c — 전체 계정 자료 추출·시도 재시작 기반

2026-09-30. P10-05/D09 및 S01~S04/S11. 현재 모델 직접 구현·코드 검토, 새 Worker/Reviewer 없음.

## 변경

- SnapshotSourceRows: V1~V16 실제 컬럼을 명시한 19종 엔터티 allowlist. 모든 SQL에 계정 조건을 바인딩하고 엔터티별 고정 순서/연속 ordinal을 사용한다. MySQL streaming +100행 batch로 원본 계정 전체를 메모리에 모으지 않는다.
- 인증 테이블/음성 원본/공용 차트/내부 object_key/삭제 preview_version/정규화 인덱스 키를 SELECT하지 않는다. 클라우드 파일은 generation/상태/해시/크기 명세만 보존하며 다운로드 권한을 보장하지 않는다.
- UUID→정규 문자열, UTC 시간→ISO 문자열, JSON 컬럼→JSON 구조, song_tier→tier를 명시적으로 변환. 과거 컨디션·삭제 표식·관계/변경 로그를 임의로 필터링하거나 삭제하지 않는다. 복합 관계는 payload의 원래 키를 모두 보존한다.
- SnapshotReadView: 동일 읽기뷰의 cursor/captured_at을 원본 batch 저장 전에 기록하는 baseline callback 추가. 쓰기는 별도 연결이며 원본 SELECT는 같은 읽기 연결을 유지한다.
- SnapshotBuildStore.restartExpired: lease가 끝난 BUILDING의 해당 attempt만 전역 capacity→header 잠금 아래 이전 파생 행 전체 삭제/예약 반환 후 새 attempt/cursor 미설정/새10분 제한으로 교체. 원본 업무 테이블은 변경하지 않는다. 이전 writer/restart/READY 재시작은 거절한다.

## 실제 검증

추출 전용 MySqlSnapshotSourceRowsTests는 새 p10_source_test_<UUID> DB에 전체 V1~V16을 Flyway로 적용했다. 모든 테스트 DB만 정리하고 사용자 DB/볼륨은 보존했다.

`gradlew.bat test --tests '*SnapshotPageCursorTests' --tests '*SnapshotPagesTests' --tests '*SnapshotReadViewTests' --tests '*MySqlSnapshotBuildStoreTests' --tests '*MySqlSnapshotSourceRowsTests' --offline --no-daemon`

관련 통합 **31 테스트 통과**, 실패0/오류0/skip0. cursor5/pages5/readview4/MySQL readview5/buildstore10/source2. 실제 MySQL8.4, P07_MYSQL_CI=true/P10_MYSQL_PORT=3307. 비밀값은 infra/.env에서 메모리로만 읽었다. 상세 로그 .local/workflow/p10-05-source-integration.log.

101곡/다른 계정 자료/합성 인증 식별자와 이메일/실제 object_key·preview_version 값 fixture로 batch 경계와 제외를 검사했다. 첫 batch 후 다른 쓰기 트랜잭션이 녹음 song_id=NULL와 cursor8을 커밋해도 사본은 cursor7/원래 song_id를 보존했다. 원본 schema/trigger를 변경하거나 테스트를 약화하지 않았다.

부분 저장 후 sink 실패 검사는 실제 저장 행이 남은 상태에서 페이지 조회409를 검증하도록 강화했다. 이 변경 후 source2를 추가 재검증했다(최종 결과는 아래 기록). 테스트 컴파일에 기존 Jackson 조회 API deprecation 안내가 있으나 테스트 실패는 아니다.

현재 모델 검토: D09의 같은 읽기뷰·완결성·계정 격리·원본 보존 및 V16 과거 컨디션 보존을 SQL allowlist/실제 diff/테스트와 대조했다. 추가 모델 자동 상향/실제 tier 적용은 확인하지 않았고, 외부 세션에 자료를 전달하지 않았다.

## 남은 범위

아직 HTTP에 노출하지 않았다. 생성 실행의 단일 소유권/지속 작업 재개, 실패/만료 정리, cleanup 후 같은 op_id 멱등성, API/OpenAPI 및 모바일 staging이 남았다. begin의 동일 attempt 재전송 자체를 여러 작업자의 실행 권한으로 해석하면 안 된다. 백그라운드 실행에 사용자 세션 토큰을 DB에 저장하지 않고 실제 job lease·ACTIVE 계정에 묶인 서버 권한을 설계·검증한 뒤 연결한다. 현재 인증은 요청 AccountAccess를 사용하므로 이 범위를 완료로 주장하지 않는다.

사용자 확인 대기0건. 새 실기·기존 기능 재검증 요청 없음. 커밋/정확 SHA CI 후속 기록 필요.

강화한 부분 저장 실패 후 조회409 검사까지 source2 재실행 통과, BUILD SUCCESSFUL. 통합31 결과와 구분해 기록한다.

최종: cd22081722b7829306e28328f8f7ff8ce7e37416 커밋/push, 필수 CI4 PASS. CI36671078688/API contract36671078674/Idempotency MySQL36671078675/Development workflow36671078690. c 기반 범위만 완료.
