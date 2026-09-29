# P10-02b — 메타정보 HTTP 송신과 원자적 승인 반영

상태: 구현/자동 검증 통과, 별도 검수 지적 해결. 커밋·CI 전이므로 완료 아님.
원본 계획 [p00579]~[p00580], 설계 [p00294]·[p00744], 기존 P10-02a와 승인된 D06을 따른다.
P10-02b가 이미 구현되지 않았음을 시작 27c5a4f 코드/이력으로 확인했다. 기존 P06 사용자 검증은 유지한다.

## 구현 범위

- LocalRepository.dispatch로 기존 인증 세션 제공 함수와 실제 HttpMutationTransport를 연결한다.
- 지원된 서버 메타정보 경로: 곡/태그 생성·일반 PATCH, 녹음 DRAFT 생성·일반 PATCH.
- 분류/곡 승인 후 녹음을 재계획한다. 선행 실패와 무관한 작업은 진행한다.
- 아직 서버/별도 계약이 준비되지 않은 목록·관계·파일·휴지통/복원/영구 삭제·SAVED 전환 명령은 전송하거나 성공 처리하지 않는다.
  P10-02 전체의 후속 경로 연결은 해당 API/파일 단계와 함께 남는다. 라이브 앱의 화면/주기 실행 연결도 별도 단계다.
- 기존 사용자 컨디션 큐/스냅샷은 보존하고 승인 없이 고정 단계로 변환하지 않는다.
- 큐 재확인·요청 확정·PENDING→SENDING은 같은 로컬 트랜잭션. 네트워크는 트랜잭션 밖에서 수행한다.
- 기존 op_id/요청 본문/로컬 request_hash를 바꾸지 않고 별도 wire 계약·경로·본문·해시를 저장한다. 토큰은 저장하지 않는다.
- SQLite v1→v2는 새 요청 테이블/불변 트리거만 추가한다. 기존 행·상대 큐 순서·파일을 다시 만들지 않는다.
- 성공은 실제 서버 응답의 ID·revision·필수 스냅샷을 확인한 뒤 서버 사본과 ACK를 한 트랜잭션으로 반영한다.
  송신 중 추가한 로컬 편집/후속 큐는 유지하며 응답으로 커서를 앞당기지 않는다.
- 계정 lease를 선점·전송 직전·응답 반영에서 확인한다. A→B→A 늦은 응답은 새 세션에 적용하지 않는다.
  이미 전송된 요청을 취소했다고 보장하지 않으며 만료된 A의 SENDING 요청은 재개 근거로 보존한다.
- 중복/canonical 응답은 기존 입력과 검증한 서버 증거를 CONFLICT로 보관한다. P10-04에서 매핑한다.
- 오류/응답 유실은 원래 요청을 보관한다. 원시 오류/토큰을 진단에 저장하지 않는다. 자동 재시도 시간표·재기동 SENDING 회수는 P10-03.

핵심 코드: apps/mobile/lib/core/sync/{mutation_request,mutation_transport,metadata_dispatcher,local_repository}.dart,
apps/mobile/lib/core/database/{account_store,account_database}.dart 및 local_schema.drift.
앱 UI·오디오·실제 사용자 DB는 이번 로컬 테스트에서 실행/변경하지 않았다.

## 에이전트/검증

작업자 Astra/high: 계정 격리·동기화·DB 이관 위험. 증거 기반 제안 후 마스터가 코드와 실제 API 계약을 대조해 구현.
Standard/default·Fast 끔 요청, 헤더의 모델/추론과 실제 미노출 tier를 구분한다. 검수자는 별도 배정한다.

- Drift build_runner 생성 성공, v2 스키마 스냅샷/이관 helper 생성.
- 초기 영향 범위 Flutter 실행: 52 통과·1 skip·1 실패. skip은 기존 Windows symlink 권한 사례이며 CI에서 실행한다.
- P10-HTTP-TEST 문제: Flutter 테스트 바인딩이 모든 HttpClient를 400으로 바꾸는 기본 mock이 원인.
  첫 보정 스크립트가 호출부와 일치하지 않아 두 번째 실행도 같은 실패. 실제 호출부에 제한된 RealHttpOverrides를 적용한 세 번째 실행에서 통과. 앱 전송 정책은 변경하지 않았다.
- 검수 전 metadata_dispatcher_test.dart: 실제 로컬 HTTP·redirect 차단·부모→자식→녹음 수정·v1 보존·동시 선점·후속 편집·계정 전환·실패 격리·불완전 응답·ACK 롤백 등 10개 통과.
- 새 코드/테스트의 스타일·빈 컬렉션 타입 수정 후 `flutter analyze --no-pub` 무경고, 종료 0.
- 상세 로그 .local/workflow/p10-*.log. 자동 테스트의 임시 DB와 합성 파일만 사용한다. 실제 폰 실기는 실행하지 않았고 기존 검증으로 새 코드를 통과 처리하지 않는다.

남은 필수 검증: 별도 요구사항/코드/실행 결과 검수, 지적 수정, 정확한 변경 SHA의 CI.
다음 작업 P10-03: 동일 요청 재시도·응답 유실 복구. P10-04 canonical 매핑/후속 PATCH baseline 재평가는 별도로 남긴다.

## 독립 검수 보완

Astra/high 검수에서 P1 응답 누락에 따른 로컬 입력 손실, P2 곡 created 플래그/HTTP 상태 불일치를 지적했다.
마스터가 요구사항/논리 위험으로 판정해 즉시 강화하고 Astra/xhigh 재검수를 배정한다.
서버의 실제 SongCreation.snapshot/SongEditing.wire와 RecordingDrafts/RecordingEditing.snapshot을 대조했다.
현재 서버가 항상 반환하는 컨디션/대표 키 필드(명시적 null 포함)를 요구하며, 누락되면 ACK하지 않는다.
곡 created는 HTTP 201/200과 일치해야 하고 신규 201 revision은 1이어야 한다.
원본 설계 p00303의 서버 충돌 값 보존을 위해 검증된 current와 revision만 별도 보관하고 로컬 입력은 유지한다.
추가 회귀 후 `flutter test --no-pub test/metadata_dispatcher_test.dart --reporter expanded`: 실제 14 통과, 종료 0.
원시 예외/서버 메시지·인증값을 보관하지 않으며, 해당 테스트는 합성 데이터만 사용한다.

재개 체크포인트: C1은 ace5703의 CI 4개 완료. P10-02b 변경은 아직 미커밋이고 Git status의 apps/mobile DB/sync/test/생성물 및 이 문서에 한정된다.
Astra/xhigh 마지막 재검수는 완료했고 별도 Astra/high P10-03 사전 분석은 완료했다. 새 세션은 프로세스와 .local의 해당 결과를 먼저 확인해 중복 실행하지 않는다.
P10-HTTP-TEST는 실패 2회 후 수정 완료(최종 14개 실행에서도 통과). 기존 ENV-GRADLE-LOOPBACK 3회는 그대로 별도 환경 항목이다.

마지막 검수 지적: conflict current revision이 로컬 기준보다 낮다는 이유로 유효한 서버 증거를 버리지 않는다.
ACK 증가/rewind 방어는 유지하고, 충돌 보관에서만 해당 하한을 제거했다. 실제 RevisionChanges/SongEditing/RecordingEditing의 응답 형태를 대조했다.
태그 CREATE의 합성 충돌 사례는 실제 태그·곡·녹음 PATCH(base 5/current 4) 세 사례로 강화했다.
`flutter analyze --no-pub` 종료 0/무경고, `flutter test --no-pub test/metadata_dispatcher_test.dart --reporter expanded` 종료 0/16 통과.
보완 스크립트 1회는 포맷된 테스트 문구를 찾지 못해 적용되지 않았다. 이후 실제 diff를 확인해 수정·16개 검증했고, 그 앞의 14개 실행을 새 회귀 근거로 쓰지 않는다.

## 실제 HTTP 충돌 응답의 교차 검증

최종 검수에서 RevisionChanges 내부 map을 HTTP 응답으로 본 지적이 있었다. 마스터는 실제 SongEditing의 wire(current),
RecordingEditing의 snapshot(owner,recording) 예외 변환을 확인했다. 내부 map에 맞춰 앱을 바꾸지 않고 실행 근거로 재검수한다.
`MetadataConflictContractTests`가 인증된 MockMvc PATCH를 통해 곡·녹음·태그 current 필드를 확인한다.
이는 H2 기반 실제 컨트롤러 파이프 검증이며 배포 서버나 폰 실기라고 주장하지 않는다.
공유 `fixtures/contracts/metadata-response-fields.json`을 Java와 Dart 양쪽 테스트가 비교한다.
`gradle test --no-daemon --tests "*MetadataConflictContractTests"`: 종료 0, 실제 3 통과·실패/오류/skip 0.
`flutter test --no-pub test/metadata_dispatcher_test.dart --reporter expanded`: 공유 필드 연결 후 종료 0, 16 통과.
Dart의 실제 TCP 로컬 HTTP 전송 테스트와 위 Spring 응답 계약 검증은 별도 실행이며 둘을 단일 실기라고 합치지 않는다.

독립 최종 판정: 실제 HTTP 변환/공유 fixture/Java 3개·Dart 16개 실행을 보고 raw-map P2 지적을 철회했다.
기존 P1/P2 수정은 유지하며 추가 입증된 수정 대상 결함 없음. 필드명 교차 검증과 실제 서버 JSON 직접 Dart 소비는 구별한다.
커밋 후 정확한 SHA의 기존 필수 CI 4개를 확인할 때까지 완료 대기다. 다음 작업자 P10-03 사전 분석 완료.

제품 커밋/푸시: `efb97f28357a3e340c3c36ea1244254cd5dcfce3`.
필수 CI 중 API contract 36554728244, Idempotency MySQL 36554728224, Development workflow 36554728269 success.
CI 36554728267은 아직 진행 중이므로 완료 대기. 새 P10-03 순수 정책 파일/테스트는 이 커밋에 포함하지 않았다.

## CI 스키마 생성 보정

CI 36554728267은 Flutter 스키마 일치 단계에서 실패했다. 서버 build/test·MySQL job은 통과했다.
문제 P10-CI-SCHEMA: 첫 CI 실패 1회. Windows CRLF 원본은 로컬 통과했으나 LF 원본으로 같은 실패를 재현했다.
차이는 v2 JSON의 trigger 원문 다섯 곳 CRLF/LF뿐이다. `.gitattributes`에 `.drift` LF를 고정하고 v2 스냅샷을 재생성했다.
v1 이력·DDL 의미·마이그레이션 코드·기존 앱 DB·개발 볼륨은 변경하지 않았다. 이전 스냅샷은 .local에 보존했다.
`dart run build_runner build` 종료 0, 재생성 후 `dart run drift_dev make-migrations --no-test` 종료 0.
수정 커밋의 필수 CI가 완료되기 전 P10-02b 완료 판정은 보류한다. P10-03 순수 정책은 별도 미커밋 준비로 유지한다.
별도 Sol/medium 검수: 줄바꿈 차이만 확인, 검사 약화/데이터 변경 결함 없음. Linux 및 정확한 SHA CI는 여전히 대기.
