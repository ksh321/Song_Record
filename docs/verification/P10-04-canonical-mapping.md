# P10-04 — canonical ID 보존 계약 대조 (구현 전)

> 최신 구현 인계는 아래 **2026-10-02 P10-04 미전송 참조 연결** 절을 따른다. 이 문서 앞부분의 구현 전 설명과 별도 작업자/검수 기록은 당시 이력으로 보존한다.

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

## 2026-10-02 P10-04 미전송 참조 연결 — IMPLEMENT 인계

R026·R036·R037·R039, 계획 p00584~p00586 및 설계 p00293~p00294에 따라 기존 P10-04a와 DECODER·ATOMIC·GATE·EXPORT·CONNECT의 보존 기반에 미전송 참조 전환을 연결했다. 기존 ID·완료 이력·사용자 확인은 유지한다. 이번 기록은 구현 인계이며 검사 통과·최종 완료 판정이 아니다.

| 완료 조건 | 구현과 검사 근거 |
| --- | --- |
| P10-04-A1 | 기존 `CanonicalSongReceipt.decode`와 소유 attempt 검사를 유지한다. `canonical_reference_store.dart`는 계정·ACK된 원래 곡 CREATE·frozen body/hash·저장 응답을 다시 대조하고 직접 alias만 인정한다. `source_token`은 해석하지 않는다. 기존 `canonical_song_store_test.dart`·`metadata_response_test.dart`를 회귀 대상으로 유지한다. |
| P10-04-A2 | `canonical_reference_plan.dart`는 PENDING/attempt=0/미동결·현재 선택·기준 일치 조건으로 `song_id`만 치환한다. 저장소는 새 op_id·별도 hash·`mutation_supersessions`·해제 근거를 같은 트랜잭션에 추가한다. 원본 payload/base_payload/hash/op_id/물리 순서는 유지한다. 확정 revision 재연결과 같은 revision의 다른 기준 거절을 새 통합 검사에 포함했다. |
| P10-04-A3 | `AccountStore.saveEdit`, `claimMutation`, `_applyCanonicalSongReceipt`에서 원자적으로 처리하고 마지막 lease 검사를 유지한다. 재개방·반복 receipt·네 지점 SQL 실패·계정 상실 시 전체 롤백 검사를 추가했다. 부가 원장과 기존 불변 트리거를 재사용하며 스키마/과거 이관은 변경하지 않았다. |
| P10-04-A4 | `mapping_eligibility.dart`는 검증된 참조 대체만 통과시키고 논리 순서를 계승한다. `metadata_followup_store.dart`는 원장 자체의 물리 순서 계약을 유지하면서 조회 시 매핑의 논리 순서를 계승한다. CREATE→연결→저장은 실제 ACK revision을 받아 기존 후속 원장으로 진행한다. `nextDispatchAt`의 미기록 미리보기, 재개방, 미지원 목록만 남을 때 예약 없음도 검사한다. |
| P10-04-A5 | 이미 시도했거나 frozen wire가 있는 요청, null/다른 곡 선택, tombstone, 불일치 기준은 보존한다. 응답 유실 후 같은 frozen 요청 재전송, 무관한 태그 전송, 기존 늦은 ACK/높은 revision/개인 편집 회귀를 유지한다. 보류 해제 근거가 불완전하면 전체 대상의 전송을 막고 즉시 예약을 만들지 않는 사례를 추가했다. |
| P10-04-A6 | `canonical_reference_dispatch_test.dart`는 고유 임시 계정 SQLite와 AccountPaths의 합성 파일을 실제 파일 인덱스·복구 저널에 등록한다. 매핑/전송/실패/재개방/계정 전환에서 원본 큐·파일 바이트/크기/hash/경로·저널·UUID·개인 곡값·녹음 스냅샷·cursor를 대조한다. 임시 경로 확인 후 해당 경로만 정리한다. |
| P10-04-A7 | 기존 테스트와 기준은 삭제·약화하지 않았다. 새 순수 계획/계정 통합 검사를 추가했다. 응답 검증 계약 대조 중 합성 키 모드의 잘못된 `SHIFT`를 기존 허용값 `MALE`로 고쳤으며 -3 키 이동의 보존 검사는 유지했다. 제품의 키 계약은 변경하지 않았다. |
| P10-04-A8 | 개인 곡 편집 후보는 OPEN 상태로 보존하며 자동 병합하지 않는다. 사용자 선택/해결 UI는 P10-07-NEXT, 목록 HTTP 송신은 P19, V33 두 기기 종합 실기는 P10-10이다. 실제 파일 업로드·백업 importer·화면 연결은 이번 완료 주장에 포함하지 않는다. P10-05는 착수하지 않았다. |

실제 변경 파일은 `account_store.dart`, `mapping_eligibility.dart`, `metadata_followup_store.dart`, 신규 `canonical_reference_store.dart`·`canonical_reference_plan.dart`, 신규 `canonical_reference_plan_test.dart`·`canonical_reference_dispatch_test.dart`와 이 문서다. 런타임 참조 흐름은 검증된 receipt → 트랜잭션 대체/보류 근거 → 공통 자격/논리 순서 → 원자적 claim → 기존 응답 검증/ACK → 재계산이다. `pendingWorkMutations`와 ACK의 로컬 draft 판정도 검증된 대체 원본을 구별하며 원본을 ACK로 바꾸지 않는다.

제어기 인계: 승인된 `canonical-tests`, `dispatch-regression`, `preservation-regression`, `analyze`, `sources-check`, `diff-check`의 실행과 현재 모델의 별도 REVIEW가 남아 있다. 이전 7개 파일 포맷은 감독 AI가 호스트 exit 0을 확인했다는 인계를 받았다. 이번 호출에서는 포맷·테스트·분석을 재실행하지 않았으며, 이후 추가한 코드/검사 부분의 포맷은 제어기에서 적용할 필요가 있다. 실행 결과·최종 대상 SHA는 아직 없으므로 통과로 기록하지 않는다. Git 쓰기·알림·CI 조회 및 실행기 변경 없이 제어기에 인계한다.

### 첫 canonical 검사 실패 보정 — 2026-10-02

제어기의 `canonical-tests` 실행 `7f1fdc22-b3fd-469e-8231-f4da948c6a6e`는 종료 코드 1이다. 해당 실행의 `stderr.log`와 `stdout.log`를 읽어 `canonical_reference_store.dart`가 Drift 생성 행과 도메인 모델의 동명 `MetadataCopy`를 함께 import하여 테스트 로딩 중 컴파일 오류가 발생한 것을 확인했다. 환경 오류가 아닌 코드의 import 충돌이며, 뒤따른 compiler exited 메시지도 같은 컴파일 실패에 연결된다.

기존 `account_store.dart`와 동일하게 `account_database.dart` import를 `show AccountDatabase`로 제한했다. `_copy`와 순수 참조 계획에는 `local_models.dart`의 `MetadataCopy`만 사용한다. 데이터 처리·스키마·테스트 기대값은 변경하지 않았다. 관련 재검사는 승인된 `canonical-tests`와 `analyze`이며 이후 나머지 지정 회귀·검사를 제어기가 수행한다. 이번 호출에서는 검사를 실행하지 않았고 수정 후 통과는 아직 미확인이다.

### 재검사 시험 자료 보정 — 2026-10-02

제어기 실행 `7f9c9cad-66b4-4426-86ed-01ec1fcaf946`의 `stderr.log`·JSON `stdout.log`를 대조했다. 앞선 import 충돌을 지난 뒤 새 통합 검사 두 사례에서 실패했으며 전체 `canonical-tests`는 종료 코드 1이다.

- 계정 상실 롤백: 복구 내보내기는 `metadata_copies`를 `entity_type,entity_id`로 정렬하지만, 시험의 별도 연결 조회에는 정렬이 없어 SONG/RECORDING 순서가 달랐다. 시험 조회에 같은 `ORDER BY`를 지정했다. 전체 테이블·모든 필드의 동등 비교와 원본 큐 `rowid AS local_order` 비교는 유지한다.
- tombstone 보존: 시험이 server_revision=0 행에 tombstone=1만 넣어 `tombstone = 0 OR server_revision > 0` 제약에서 중단됐다. 양수 revision=2 및 동일 revision의 PURGED 서버 snapshot을 함께 구성하고 미전송 CREATE·로컬 입력은 그대로 둔다. 매핑 이후 삭제 snapshot과 로컬 입력이 포함된 해당 metadata 행 전체가 보존되는 검사도 추가했다. 제품 코드와 DB 제약은 변경하지 않았다.

연결 완료 조건은 P10-04-A3·A5·A6·A7이다. 수정 파일은 `canonical_reference_dispatch_test.dart`와 이 기록이며 기존 사용자 변경·완료 이력은 보존한다. 재검사 `canonical-tests`·`analyze`와 나머지 계획 검사는 제어기에 인계한다. 이번 호출에서 포맷·테스트·분석을 실행하지 않았으며 수정 후 통과를 주장하지 않는다.

### 현재 모델 REVIEW 지적 보정 — canonical 후속 저장과 충돌 해결 연결

제어기가 제공한 수정 전 검사 결과는 6개 그룹 PASS이며, 현재 모델 REVIEW는 P10-04-A4·A7에 대해 승인하지 않았다. `_canFollow`가 후속 대체 원장만 투영하고 충돌 해결 원장을 적용하지 않아, canonical CREATE → 메모 PATCH의 409 → 명시적 LOCAL 해결 → 해결 요청 ACK 뒤에도 원래 CONFLICT 요청을 선행 작업으로 판단하는 경로가 확인됐다. 해당 조합은 당시 실행 재현 없이 코드 경로 대조로 지적했으며 환경 오류가 아니다.

`canonical_reference_store.dart`의 보류 해제 판정에 공통 전송 경로와 같은 `metadataFollowupEligibility` → `applyConflictEligibility` 순서를 적용했다. 검증된 해결 원장의 대체·논리 순서를 계승하고, 후보 자체의 자격 및 모든 유효 선행 요청의 실제 ACK를 확인한 뒤 기존 후속 계획으로 해제를 판단한다. 유효하지 않은 해결 근거의 격리도 유지한다. 원본 큐/CONFLICT를 ACK로 바꾸거나 보류를 일괄 해제하지 않는다.

`canonical_reference_dispatch_test.dart`에 두 통합 사례를 추가했다. 매핑 전 CREATE·메모·저장을 큐에 넣고 메모 충돌 후 재개방하여 LOCAL을 선택한다. 해결 요청의 정상 ACK 및 응답 유실 후 재개방·명시적 재시도·동일 frozen 요청 ACK 각각에서 후속 저장이 revision 3을 기준으로 이어지는지 검사한다. 해결 전/미승인 재시도 상태에는 저장 보류가 유지돼야 하며, 예약 조회는 쓰기를 발생시키지 않아야 한다. 원본 미전송 큐 전체, 충돌 큐와 frozen wire, 해결 원장·논리 순서, 저장의 실제 선행 ACK, 최종 로컬/서버 snapshot, 등록 합성 파일·저널·cursor 및 재개방 후 예약 종료를 대조한다.

이번 수정은 P10-04-A4·A7 지적을 처리하며 A3·A5·A6 보존 조건도 연결한다. 수정 전 PASS는 이 변경의 통과 근거로 재사용하지 않는다. 이번 호출에서는 포맷·테스트·분석을 실행하지 않았으며 추가 코드의 포맷과 `canonical-tests`, `dispatch-regression`, `preservation-regression`, `analyze`, `sources-check`, `diff-check` 및 후속 REVIEW는 제어기에 인계한다. P10-07-NEXT의 선택 UI, P19 실제 목록 송신, P10-10 두 기기 실기 경계와 기존 완료 이력은 유지하며 P10-05에는 착수하지 않는다.

### 충돌 해결 응답 유실 검사의 예약 기대값 보정 — 2026-10-02

제어기 `canonical-tests` 실행 `262ec5a7-fbd9-4c4c-849b-98e56faf0d88`의 `stdout.log`·`stderr.log`를 읽었다. 숨김 항목을 제외한 결과는 148개 성공·1개 실패(제외 0), 그룹 종료 코드 1이다. 새 정상 ACK 사례는 통과했고, 응답 유실 사례는 `canonical_reference_dispatch_test.dart`의 예약 조회에서 null 대신 `2030-01-01T00:01:00Z`를 받아 실패했다. 이후 재시도·저장 구간은 해당 실행에서 도달하지 못했으므로 통과로 세지 않는다.

원인은 새 시험의 기대값 오류다. 기존 `RetryPolicy.automaticFailure`는 `RESPONSE_LOST/200`을 일시 실패로 분류하고 최초 실패 뒤 1분을 예약한다. `RetryControls`와 `nextDispatchAt`은 이 미래 예약을 조회하되 만료 전 claim을 허용하지 않는다. `retry_policy_test.dart`와 `mutation_retry_test.dart`의 기존 계약도 동일하며 제품 재시도 정책은 변경하지 않았다.

해당 사례에서 정확한 1분 뒤 예약, RETRY/AUTO·attempt=1·자동 재시도 사용량=0을 검사하도록 수정했다. 예약 조회 및 만료 전 claim 거절 전후에 복구 테이블 전체가 같아야 하며, 명시적 재시도 승인만으로 시도·예산을 소비하거나 저장 보류를 해제하지 않는 검사도 추가했다. 실제 수동 ACK 뒤 attempt=2·MANUAL·자동 사용량=0 및 기존 동일 frozen 요청·후속 저장·파일/저널 보존 검사를 유지한다. 해결 요청의 재시도 예약과 아직 ACK되지 않은 후속 저장의 보류를 구별하며 P10-04-A4·A5·A6·A7의 기준을 낮추지 않는다.

수정 파일은 `canonical_reference_dispatch_test.dart`와 이 문서다. 테스트·분석·포맷 실행 및 실행기 상태 변경 없이 `canonical-tests` 재검사와 나머지 지정 검사·REVIEW를 제어기에 인계한다. 이번 수정 후 결과는 미확인이고 P10-05는 착수하지 않는다.
