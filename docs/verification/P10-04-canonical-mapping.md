# P10-04 — canonical ID 보존 계약 대조 (구현 전)

최신 상태: P10-04a 부가 v4 저장 기반은 `5c23040abf78e34ea537016545ab78244764a79d`로 통합·푸시했고 [별도 검증 기록](P10-04a-preservation-schema.md)에서 추적한다. 아래 “제품 코드 아직 없음/v3”는 최초 계약 대조 당시 기록이다. 전체 P10-04 원자 매핑은 아직 완료가 아니다.

P10-04b 준비에서 서버 `SongCreation.create/existing`을 다시 대조했다. 인증 계정의 검증된 TJ proof 번호로 reserved_tj_number를 조회하고, existing은 source_type/번호 일치와 ACTIVE를 검사한 후 200/created=false를 반환한다. 따라서 source_token을 TJ 문자열로 해석할 필요가 없다. 새 receipt decoder는 기존 전체 snapshot 검증을 유지하고 이 서버 계약에 연결해야 한다.

현재 recoveryData의 실제 앱 소비는 main.dart의 복구 자료 저장이며 저장소 검색에서 이 형식의 importer는 찾지 못했다. 버전/순서 계약과 미구현 복원 경계는 후속에서 명시한다. 기존 saveEdit fingerprint가 요청 당시 draft를 포함하지만 큐에는 해당 draft가 없으므로 최신 draft로 원래 fingerprint를 재구성하지 않는다. 자동 successor는 별도 결정적 계약/회귀를 준비한 뒤 구현하며, 단순 보류만으로 전체 매핑을 완료 처리하지 않는다. 다음 작업자의 제안은 실제 파일 변경이나 테스트 통과 증거가 아니다.

기준 HEAD `c6c1eaacd41b7318aeadfc48953bd356e570eedc`. P10-03b UI/스케줄러와 파일 범위를 분리한 준비 작업이다. 이 문서는 구현 완료나 테스트 통과 증거가 아니다.

## 원본과 현재 코드

- [계획 검색본](../reference/search/plan.txt) p00584~p00586: 같은 TJ 곡의 canonical ID를 받아 대기 녹음·목록 참조를 로컬 트랜잭션으로 바꾸고, 녹음 UUID·파일·다른 개인 편집을 보존한다.
- [설계 검색본](../reference/search/design.txt) p00293: 중복 생성의 메모·키·버전으로 서버 값을 덮어쓰지 않고 값 차이를 사용자 선택 편집으로 보관한다. 원본 경로와 해시는 [manifest](../reference/search/manifest.json)에 연결돼 있다.
- `services/api/src/main/java/com/ksh321/songrecord/api/songs/SongCreation.java`: 인증 계정의 예약 TJ 번호로 기존 곡을 조회한다. ACTIVE 중복은 HTTP 200/created=false/canonical_song_id/song, 신규는 201/true를 반환한다. TRASHED·PURGE_PENDING·PURGED는 별도 오류이며 자동 매핑 성공으로 취급하지 않는다.
- `SongApiIntegrationTests.twoDevicesConvergeThenEditSelectAndReadOneCanonicalSong`: 기존 artist/version 보존, 새 UUID 행 미생성, 이후 편집 뒤 동일 op 응답 불변을 검사한다. 여기서는 소스를 대조했으며 해당 테스트를 새로 실행하지 않았다.
- `apps/mobile/lib/core/sync/metadata_dispatcher.dart`: 생성 envelope와 snapshot을 검증하지만 다른 UUID를 `CANONICAL_MAPPING_REQUIRED`로 보관할 뿐 매핑하지 않는다.
- `local_schema.drift`: 원본 queue identity/payload/hash와 frozen wire는 불변이다. `account_database.dart`는 현재 v3이며 다음 이관은 명시적으로 추가해야 한다. 기존 v1/v2/v3 내용을 덮어쓰지 않는다.
- `dependency_planner.dart`: RECORDING의 선택적 song_id, PLAYLIST_ITEM의 필수 song_id/playlist_id가 현재 알려진 참조다. `MutationRequest.prepare`의 실제 송신 경로는 songs/recordings/tags뿐이다. 목록 참조 보존과 목록 서버 송신 완료는 구분한다.
- `AccountStore.recoveryData()`는 내보내는 테이블을 열거한다. 새로운 alias·대체·보류·편집 보관 자료도 포함해야 한다. 복구 입력/왕복 계약은 구현 전 추가 확인 대상이다.
- `recording_journals.recovery_payload`는 객체 JSON이며 저장 API는 임의 객체를 받는다. 현재 앱 lib 검색에서 readJournal의 외부 호출은 찾지 못했다. 내부 필드 계약을 추정해 문자열 치환하지 않는다. 파일 경로·해시·녹음 UUID·journal operation_id는 유지한다.

## 구현 방향과 보존 조건

별도 작업자 Astra/high 제안을 실제 코드와 대조했다. DB·계정·멱등 요청 변경 위험 때문에 이 수준을 선택했다. default/Fast 끔은 요청값이고 실제 서버 tier는 미확인이다.

1. 검증된 SONG CREATE 200/created=false의 다른 UUID 응답을 전용 트랜잭션으로 반영한다. 신규 201의 다른 UUID, 미검증 과거 충돌 저장값만으로 alias를 만들지 않는다. source_token은 서버 검증 자료이며 클라이언트가 TJ 번호와 같다고 가정하지 않는다.
2. alias·원본 응답·양쪽 최신 draft·값 차이를 보존한다. canonical의 더 높은 revision/tombstone 또는 기존 local draft를 오래된 receipt로 덮어쓰지 않는다. source metadata 행도 보존한다.
3. 알려진 로컬 녹음/목록 참조를 함께 바꾼다. 안전한 미송신 요청(attempt=0, PENDING, frozen wire 없음)은 새 op_id의 대체 요청으로 연결할 수 있다. 원본은 서버 ACK로 위장하지 않고 별도 대체 이력으로 실행 대상에서 제외한다.
4. 대체 요청은 원본의 논리 순서를 이어받는다. 조회/planner뿐 아니라 claim·수동 승인·예약 계산에서도 대체/보류를 확인한다. 이미 시도한 요청은 새 op로 자동 교체하거나 예산을 초기화하지 않는다.
5. 서버가 처리한 원래 곡 CREATE만 receipt 근거로 ACK할 수 있다. 개인 편집값 반영까지 완료한 것으로 확대하지 않는다. 후속 PATCH·이미 서버에 있는 녹음의 재연결·미지원 목록 송신은 별도 상태로 보존한다.
6. 부가 테이블 이관은 처음 빈 상태로 만들고 기존 TJ 유사성만으로 매핑하지 않는다. 계정 소유·alias 순환/재지정·대체 중복을 막으며 기존 queue/wire/예산/cursor/파일을 보존한다.

자동 값 병합이나 관계 중복 삭제 정책은 추가하지 않는다. 위 보존 요구 자체는 원본 근거가 있어 사용자에게 다시 정책 승인을 요청할 사항이 아니다.

## 다음 검증과 재개 위치

다음은 저장소의 계정 lease/claim 직렬화 및 journal·복구 계약을 확인한 뒤 v4 부가 이관과 원자 매핑을 구현하는 것이다. P10-03b에 대한 사용자 응답을 P10-04의 통과 근거로 사용하지 않는다.

별도 Astra/high 문서 검수에서 아래 구현 전 확인 사항을 추가했다. 설계 확정/제품 검수 통과로 표현하지 않는다.

- 이미 시도한 frozen 요청은 planner의 baseline/참조 검사를 우회할 수 있다. 기존 UUID 참조 요청의 결과 재확인 전송, 보류, 늦은 응답 반영 조건을 구현 전에 정한다. 일괄 차단이나 새 op 재송신으로 해결하지 않으며 기존 예산 유지·응답 유실·매핑 전후 경합을 검증한다.
- 현재 planner는 서로 다른 source/canonical UUID를 다른 대상으로 본다. 두 요청열을 합칠 때 계정 DB의 기존 논리 순서와 보류 선행 요청을 기준으로 직렬화하여 후속 요청이 추월하지 않게 해야 한다. 양쪽 UUID에 PATCH가 남은 경우를 회귀 검증에 포함한다. 자동 rebase/편집 병합은 추가하지 않는다.
- 서버 테스트의 artist/version 보존 검사는 모바일 note/key의 별도 편집 보관 증거가 아니다. 모바일 양쪽 최신 draft·후속 PATCH·대표 key와 녹음 key 구분을 새 테스트로 증명해야 한다.

필수 검증: 중간 실패 rollback, 반복 receipt에서 대체 중복 방지, 원본 요청 미변경·미송신 ACK 금지, 후속 순서, 기존 편집/높은 revision/tombstone 보존, 계정 격리, 재시작/이미 시도한 요청의 예산 유지, v1/v2/v3 이관, 파일/UUID 보존, 복구 자료 보존. 실제 실행 전 개수나 결과를 기록하지 않는다.

현재 결과는 소스 대조와 구현 방향 정리뿐이다. 스키마/제품 코드 변경·신규 테스트·폰 실기·P10-04 커밋/CI는 아직 없다.
문서 보완에 대한 별도 Astra/high 최종 검수는 추가 잘못된 단정 없음으로 회신했다. 이는 구현 검수 통과가 아니다.

후속 Astra/high 작업자에게 실제 계정 직렬화/queue/wire/스키마를 제공해 v4 부가 테이블·트리거와 매핑 순서 제안을 받았다. master가 메모리 SQLite에서 제안 DDL과 기존 스키마를 결합해 4개 테이블 생성, 정상 alias 1건, 잘못된 created 값 3종 및 alias 수정/삭제 거부 2종, foreign_key_check 정상임을 확인했다. 최초 추출 스크립트는 SQL 블록 수 가정(2개, 실제 DDL 2개+조회 1개)에서 중단했고 조회 블록을 제외하도록 수정했다. 사용자 DB/파일은 접근·변경하지 않았다. 이는 Drift 생성/이관/앱 통합/복구 왕복 검증을 대신하지 않는다. 제품 코드는 아직 적용하지 않았다.
