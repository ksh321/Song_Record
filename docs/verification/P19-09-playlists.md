# P19-09 — 제거와 삭제 연결

## 원본·완료 조건
- 계획서 v1.0 문단893~895: 항목 제거·목록 삭제는 Song·Recording을 삭제하지 않고, 곡 휴지통 이동 때 관련 항목만 숨긴다. V26·V34·V37·V38을 대조하며 복원 연결은 P20이다.
- 구현설계서 v1.11 직접 문단818~820: DELETE /playlists/{id}/items/{itemId}, base_revision, 항목만 제거. D07의 목록 영구 삭제 확인·큐·원장·정리 Job·곡/녹음 보존은 유지한다.

## 구현·별도 검토
- 서버 항목 제거에 소유권·부모 revision·숨김 상태를 검증하고, 항목 제거·삭제 UUID 원장·부모 버전 증가·전체 집계 DELETE 피드를 한 트랜잭션으로 연결했다. 다른 목록·항목 위치·Song·Recording은 변경하지 않는다.
- 모바일은 목록에서 제거 확인/취소, 한 부모의 선행 미확정 작업 차단, 불변 DELETE 요청 재시도, 응답의 정확한 잔여 구성·항목 정체성 검증·원자적 ACK를 연결했다. 잘못된 응답은 DB를 보존한다.
- 목록 생성/이름 변경/삭제의 afterSave를 기존 동기화 콜백에 연결했다. D07의 삭제 확인 문구·복원 불가·송신 대기 안내를 유지한다.
- hideTrashedSong은 P20의 실제 곡 삭제 트랜잭션 안에서 호출하는 목록 연계 함수다. 같은 계정 삭제 배치·deletion_item의 대상 Song·TRASHED 상태를 검증하고 활성 부모를 ID 순서로 잠근다. 항목 ID·위치·곡 연결은 그대로 두고 hidden_by_batch_id와 부모 revision만 갱신한다. 변경 피드에는 숨긴 항목도 포함해 영구 삭제로 오인하지 않는다. 현재 휴지통 API·화면·복원은 후속 P20 범위이며 완료로 확대하지 않는다.
- 일반 집계 응답에서 빠진 기존 숨김 항목을 영구 삭제 표식으로 바꾸던 수신 경로를 수정했다. 부모 영구 삭제와 명시적 항목 DELETE에는 기존 tombstone 처리를 유지한다.
- P19-08 순서 요청 이름을 원본 설계 문단825의 ordered_item_ids로 정렬했다. 단순 item_ids는 다중 추가 응답 계약에만 남긴다. 이미 완료한 시험 요청은 ACK 상태이며 이력·커밋은 재작성하지 않는다.
- 현재 gpt-6.1-sol/medium이 구현 뒤 원본·실제 diff·멱등/계정/삭제 경계·실행 근거를 별도 검토한다. 별도 모델·하위 에이전트 호출 없음.

## 검사 근거·수정 기록
- 최종 모바일 영향4개 PASS: 제거 손상 응답 롤백·동일 hash 재시도·남은 위치·곡 및 녹음 보존·숨김 근거 보존·재시작, 전체 목록 삭제 후 곡 보존, 순서 계약 회귀.
- 최종 PlaylistTests 영향 PASS: 항목 제거의 다른 목록/곡/녹음 보존·멱등·revision/다른 목록 거절, 곡 휴지통 연계 함수의 다중 목록 숨김·직접 곡 비영향·ID/위치 보존·피드 검증. 최초 기기 UUID 문자열 타입 및 시험 트랜잭션 준비를 정정했다.
- 첫 전체 Flutter는 978 PASS·1 FAIL(숨김 보존 새 회귀). 최종 소스의 영향 검사4개는 PASS이며 실패 로그를 .local/workflow/p19-09/mobile-tests-before-final.log에 보존했다. 현재 최종 일괄 검사 진행 중으로 결과 확인 전 전체 통과라고 하지 않는다.
- V26: multiSelectionIsAtomicIdempotentAndScopedToEachPlaylist, V34: playlist_discovery_test의 KY→TJ/취소와 P19-07 실기, V37: creationLinksOnlySameOwnerNumberAndActiveParentWithoutChangingIdentityOrOrder, V38: registeredTjAndManualEntriesReuseCanonicalPositionWithoutRevisionBump 및 KY/forged 후보 거절. 최종 전체 검사로 회귀 대조한다.
- 실제 MySQL 항목 제거·멱등 재전송·Song 보존은 최종 SHA 필수 CI에서 확인한다. 설치본 확인 및 최종 CI는 아래에 추가한다.

## 변경 파일·학습 개념
- API PlaylistService/Controller/Configuration, PlaylistTests/MySqlIdempotencyTests, OpenAPI.
- 모바일 playlist_library/detail/library_screen, mutation_request/dependency_planner/playlist_addition_receipt/account_store/retry_controls/playlist_change_store 및 테스트·검증 fixture.
- 목록 구성 삭제와 원본 데이터 삭제는 다른 변경이다. 숨김은 복원할 관계를 남기고, 영구 삭제 표식은 늦은 동기화 응답으로 되살아나는 것을 막는다.

## 최종 로컬·설치본·검토 결과
- Flutter 전체 979개 PASS(129.37초), API build --offline PASS(62.21초), 최종 analyze 문제0(9.75초), API 계약 PASS(2.66초), 검증 APK PASS(37.30초), diff --check PASS. 분석의 중괄호9건·명시 타입1건만 정리 후 최종 통과했으며 테스트 삭제/약화 없음.
- SM_A546S install -r로 기존 데이터 유지. 별도 합성 계정1909·실제 SQLite 앱에서 제거 취소→두 곡 보존, 첫 항목 제거 확정→직접 등록 곡만 남음, 재시작 후 같은 한 곡 유지. 목록 영구 삭제의 D07 문구·취소→목록 유지, 확정→빈 목록, 재시작 후 빈 목록 유지. XML cancel-preserved/removed/delete-dialog/list-preserved/removal-persisted/deleted/deleted-restart-ready 보존. 초기 로딩의 빈 화면은 완료 근거로 사용하지 않고 로딩 후 화면을 재확인했다.
- 현재 모델 최종 별도 검토: 정확한 소유 목록·항목 범위, 한 revision/원장/피드 트랜잭션, 요청 불변성, 손상 응답 롤백, 숨김 복원 근거 보존, 계정 전환 후 오래된 화면 저장 거절, 원본 API 필드, 곡/녹음 보존 검사와 실제 취소·재시작을 대조. 지적 수정 완료. P20 전체 휴지통 API/복원은 별도 후속 범위로 유지.
- 사용자 직접 할 일0건. 최종 SHA 필수 CI 3종은 푸시 후 확인한다.
