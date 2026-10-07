# P10-06e — 증분 변경 수신: 계정 저장소 원자 적용 기반

2026-10-01. 원본 계획 p00590~592, 설계 p00303/307/311~312의 성공 적용 뒤 커서 저장 및 초안·삭제 표식 보존에 근거한 세부 작업. AccountStore 직렬 실행 안에서 ChangeFeedStore가 단일 SQLite 트랜잭션으로 반영한다. DB 버전/기존 테이블을 바꾸지 않는다.

범위: SONG/RECORDING/PLAYLIST/TAG/CONDITION의 식별자·revision이 있는 서버 사본과 DELETE 표식을 metadata_copies에 반영한다. 현재 적용 사본 token·계정·시작 cursor·baseline_complete를 확인하고 마지막 fence 후 커밋한다. 부분 오류/계정 변경/커서 쓰기 실패는 앞선 행까지 롤백한다. 더 새로운 ACK/초기 revision과 기존 tombstone을 되돌리지 않는다. 미전송·충돌·실패 큐, mapping hold 또는 다른 로컬 초안이 있으면 local_payload를 보존한다. 큐/base_payload/wire/이력/파일/초기 스냅샷은 변경하지 않는다.

검토 보완: PLAYLIST_ITEM에는 일반 revision이 없고 RECORDING_ASSET은 cloud_revision/generation 계약이다. 이 두 타입은 전용 적용기가 완성될 때까지 전체 페이지를 거절하고 커서를 유지한다. 초기 DELETION_LEDGER는 ledger UUID와 entity_id가 다르다. 대응 원장 발견 시 단순 skip하고 cursor를 넘기면 metadata view에 삭제 반영이 없을 수 있어, 전용 투영이 필요하다는 오류로 전체 롤백하도록 보완했다. 사용자의 정책을 새로 만들거나 삭제 원장을 일반 DTO로 위조하지 않았다.

검증:
- flutter test --no-pub test/change_feed_store_test.dart test/snapshot_download_store_test.dart test/change_feed_transport_test.dart test/change_feed_response_test.dart --reporter expanded: 최종 **39 PASS**.
- flutter analyze --no-pub lib/core/database/change_feed_store.dart lib/core/database/account_store.dart test/change_feed_store_test.dart test/snapshot_download_store_test.dart: **No issues found**.
- git diff --check: 통과.

실제 SQLite 최종 fence 롤백, 늦은 잘못된 행 롤백, cursor 쓰기 실패, 동일 cursor의 사본 교체, 다른 계정, 중복 응답, 새 revision 보존, 삭제/재생성 방지, 미지원 관계 거절을 검사했다. 실제 임시 계정 DB를 닫고 다시 열어 cursor8과 서버 revision2를 확인했다. 복구 내보내기의 나머지 모든 테이블을 전후 비교하고 4바이트 합성 audio 파일도 보존됨을 확인했다. 휴대폰 녹음·청취 결과가 아니다.

테스트 자료 오류: 교체용 manifest의 토큰을 바꾸지 않아 CHECK 제약에서 두 사례가 실패했다. manifest token/행 수를 일치시켜 수정했으며 제약을 약화하지 않았다. 이후 현재 모델 검토에서 원장 skip 위험을 발견해 fail-closed로 수정하고 전체39개를 재실행했다. 로그 .local/workflow/p10-06e-reviewed.log.

남은 범위: 각 업무 DTO의 전체 필드 검증, 관계/asset 전용 적용, 초기 영구 삭제 원장 투영, 수신 실행기·상태 안내·앱 연결. 현재 앱 자동 동기화에서는 이 새 저장소 메서드를 호출하지 않으며 전체 P10-06 완료가 아니다. 폰 테스트 대상은 계속 e4adb7f. 별도 에이전트 없이 현재 모델이 코드/원본/검증을 재대조했다. 실행 모델/속도 변경 주장은 하지 않는다. 보완 코드는 커밋 후 통합 SHA 필수 CI로 확인한다.

## 2026-10-01 — 남은 관계 계약의 과거 맥락 상담

기존 ChatGPT ‘노래 기록 → 워크플로우 순서 검토’(6abb447a-d7f0-83ee-94bc-b57f744407c5)를 read_thread로 실제 읽을 수 있음을 확인했다. send_message_to_thread로 기존 합의 유무만 질문했다. 목적은 과거 맥락 상담이고 새 Codex 구현/검수 위임이 아니다. 전달 범위는 비밀값 없는 엔티티·버전 필드와 아래 쟁점이며 코드 원문/계정 자료/로그/인증 설정은 전달하지 않았다.

- PLAYLIST_ITEM에는 자체 revision이 없고 원본은 부모 Playlist revision으로 항목/순서를 변경한다. 증분 envelope의 revision 및 순서 교체 payload를 이전에 확정했는지.
- RECORDING_ASSET의 cloud_revision/generation과 envelope revision을 대응시키는 기존 규칙이 있는지.
- writer를 P10에서 전부 구현하거나 P19/파일 기능에서 연결하기로 한 명시 합의가 있었는지.

새 제안을 과거 결정으로 취급하지 않고 기존 근거가 없으면 없다고 답하도록 요청했다. 답변 미수신 상태이며 현재 코드에 임의 채택하지 않았다. 사용자 직접 행동은 없고 이 상담에 의존하지 않는 수신 보완/CI 확인을 계속한다.

상담 답변 확인: 질문2741063d-f9d7-4c88-80d3-ab25ec9719ec, 답변83ec7983-c97e-5125-9e42-de48f744bedb(2026-10-01). 원본의 부모 Playlist revision·cloud_revision/generation 용도는 확인되지만 정확한 증분 payload와 writer 구현 시점은 미확인이다. 상담 측의 과거 대화 검색 오류 때문에 ‘합의가 없었다’고 단정하지 않는다. 현재 V4/SnapshotSourceRows/AccountChanges와 대조해 같은 결론을 확인했다. 새 정책 승인·P10 유예/완료 근거로 사용하지 않는다.

질문 표현 정정: 원본 P10-06은 ‘업무 변경·삭제 표식을 적용한 로컬 커밋 뒤에만 마지막 change_seq를 갱신’이다. 같은 SQLite 트랜잭션은 이 보장을 위한 현재 구현 선택이며 원문 직접 인용이 아니다. 기존 원자성 검증은 유지한다.

다음 실제 작업: PLAYLIST_ITEM의 부모 버전과 RECORDING_ASSET의 cloud_revision/generation을 별도 수신 계약으로 명시한 뒤 현재 저장소 코드/원본 보존 규칙에 맞춰 적용기·테스트를 구현한다. 상담이 미확인이라고 사용자 승인이나 작업 유예가 생긴 것으로 간주하지 않는다. P10-09 현재 분석에서 RecordingDrafts는 없는 곡404/비활성 곡SONG_NOT_ACTIVE를 반환하며 DependencyPlanner는 삭제된 참조 전송만 막는다. 이것을 새 오프라인 녹음의 미연결 저장 완료로 표시하지 않는다. 원래 op_id·시도/wire·녹음 UUID/파일 보존을 포함한 실제 연결 처리가 남아 있다.

## 2026-10-01 — P10-06e/P10-06m 파일 상태의 초기·증분 수신

근거: 원본 계획 p00587~592, 설계 p00332~337/p00708/p00741, DB V2/V3 recording_asset, SnapshotSourceRows의 실제 공개 필드. 과거 상담은 상세 wire 합의 미확인이라고 답했으므로 아래는 현재 코드에 근거해 명시한 수신 계약이며 과거 승인으로 가장하지 않는다. 서버 파일 변경 writer는 아직 구현되지 않았다.

- UPSERT payload는 SnapshotSourceRows와 같은 recording_id/cloud_state/blocked_reason/generation/verified_size/sha256/stored_at/cloud_revision/created_at/updated_at 필드다. user_id가 있으면 현재 계정과 같아야 하며 초기 사본에는 필수다. envelope entity_id는 recording_id, revision은 cloud_revision과 일치해야 한다. 내부 metadata_copies에만 id/revision 별칭을 추가하며 원본 payload는 보존한다. object_key나 불명확한 필드는 받지 않는다.
- 파일 상태 버전은 녹음 revision과 비교하지 않는다. STORED/DELETING은 검증된 파일 필드를 요구하고 같은 generation의 확정 크기·해시는 뒤늦은 정책 변경으로 바꾸지 않는다. 같은 버전의 서로 다른 내용은 거절한다. 시각으로 충돌을 해결하지 않는다.
- NONE은 서버 파일 상태이며 녹음·로컬 파일 삭제가 아니다. 미전송 입력/원본 snapshot은 보존한다. 유효하지 않은 후반 응답은 앞선 변경 및 cursor와 함께 롤백한다.
- 아직 generation DELETE/삭제 원장 적용은 전용 처리가 남아 있어 거절하고 cursor를 유지한다. 전체 P10-06 완료가 아니며 이 항목을 이유로 독립 작업을 중단하지 않는다.

변경: recording_asset_projection.dart, change_feed_store.dart 및 관련 두 테스트. 현재 모델 코드 검토에서 동일 cloud_revision의 다른 내용과 동일 generation의 checksum/크기 변조를 추가 차단했다.

실행: `flutter test --no-pub test/recording_asset_projection_test.dart test/change_feed_store_test.dart test/resync_integration_test.dart --reporter expanded` **52 PASS**. 변경4파일 `flutter analyze --no-pub` **No issues found**. 테스트 작성 중 cursor helper 선언 순서 오류를 수정했다. 잘못된 로그/테스트 경로 및 실행 디렉터리는 명령 오류로 별도 수정했으며 테스트 통과로 기록하지 않았다. 분석 스타일 지적4개도 해소했다. 원본 검사를 삭제/약화하지 않았다. 상세 로그 `.local/workflow/p10-asset-receiver-reviewed.log`.

현재 사용자 행동 없음. 폰 설치/실기 실행 없음. 기존 USER-025 확인 범위를 이 변경에 확대하지 않는다. 다음 실행은 generation 삭제 원장 보존 처리와 목록 항목 관계 수신이다. 실행 모델·속도 변경 기능은 미확인, 별도 에이전트 없이 현재 작업에서 구현·검토했다.

## 2026-10-01 — P10-06e/P10-06m 파일 세대 삭제 증거 수신

앞 절의 generation DELETE/원장 미지원은 아래 후속 변경으로 보완했다. 같은 녹음의 새 객체 세대는 허용하고 삭제된 이전 세대 재노출은 차단한다. 원본 설계 p00741 및 DB V6의 녹음 UUID와 object_generation 별도 원장에 근거한다.

- ASSET DELETE의 정확 payload는 recording_id/generation/cloud_revision/purged_at이다. envelope ID·revision과 일치해야 한다. 초기 원장은 실제 SnapshotSourceRows 필드를 검증한 뒤 같은 내부 증거로 변환한다. 서버 writer는 아직 없어 이 계약의 end-to-end 서버 발행 검증은 남아 있다.
- 새 스키마/마이그레이션 없이 기존 metadata_copies의 DELETION_LEDGER 영역에 generation을 키로 한 **파생 증거**를 저장한다. 원본 서버 원장 UUID나 원본 snapshot을 바꾸지 않는다. 이 영역의 server_payload는 위 4필드, server_revision은 cloud_revision, tombstone=1이다. 녹음·파일 사본 UUID의 영구 삭제와 혼동하지 않는다. 일반 UUID 삭제 원장은 기존 처리대로 유지한다.
- 파일 상태가 삭제 증거의 generation과 같을 때만 NONE으로 투영하며 파일 세대·크기·해시·저장 시각은 서버 노출용 사본에서 비운다. 실제 로컬 파일·파일 참조·녹음 정보·로컬 입력·큐는 삭제하지 않는다. 다른 새 generation의 현재 상태를 오래된 삭제 응답이 지우지 못한다. 더 높은 버전으로 삭제 세대를 재노출하거나 같은 generation을 다른 녹음에 재배정하는 응답은 거절한다.
- 증거 저장·사본 반영·cursor 이동은 계정 단일 트랜잭션이다. 계정 해제/잘못된 후반 행은 증거까지 롤백한다. 매 페이지 기존 증거를 DB에서 다시 읽어 유지한다. 중복 증거는 내용 일치만 허용하며 현재 코드에 파일 삭제 권한은 없다.

현재 모델 직접 구현 후 별도 코드 검토: 원본/DB 세대 유일성, 삭제와 새 세대 재업로드 구분, payload-캐시 버전 일치, 계정 경계·원자성, 초기 원본 및 파일 참조 보존을 대조했다. 후속 없는 무한 재시도나 시간 기준 덮어쓰기는 추가하지 않았다.

검증: 관련 change_feed_store/recording_asset_projection/resync_integration 3파일 **59 PASS**, 변경3파일 분석 **No issues found**, diff 검사 통과. 새 검증은 삭제 뒤 다음 페이지 재노출 차단, 새 generation 허용 및 오래된 삭제 무효, 빈 초기 사본 페이지의 원장 반영, 원본 보존, 늦은 오류·계정 해제 롤백, 다른 녹음/계정 거절을 포함한다. 합성 파일 DB 참조를 비교했으며 사용자 실제 파일 청취·실기 결과가 아니다.

테스트 자료 수정: local_recording_files의 실제 local_state/검증 필드를 사용하도록 보완했고, 타 계정 원장은 수신기 이전 DB owner CHECK가 먼저 거절함을 확인해 그 정확 제약과 적용기 자체 계정 검사 모두를 테스트했다. 제약 우회·테스트 약화 없음. 로그 `.local/workflow/p10-asset-deletion-reviewed.log`. 앞 수신 커밋 ad8ac50의 필수 CI3 PASS/CI 실행 중 확인. 전체 P10-06 완료 아님; 다음은 목록 항목 관계 수신과 남은 통합 검증이다.

## 2026-10-01 — P10-06 증분 변경 수신: 목록 전체 항목의 원자적 적용

근거: 원본 계획 p00590~592, 부모 Playlist revision으로 항목/순서를 변경하는 설계와 V4 실제 필드. 아래는 현재 구현의 명시적 수신 계약이다. 과거 상담에서 확정된 wire 계약으로 주장하지 않는다. 서버 목록 writer 연결/실제 HTTP 발행 검증은 남아 있다.

- 한 논리 작업의 payload는 `playlist` 전체 헤더와 `items` 전체 항목 배열이다. 숨긴 항목도 포함하며 서버에서 제거한 항목만 배열에서 빠진다. envelope PLAYLIST는 부모 ID, PLAYLIST_ITEM은 대상 항목 ID이며 revision은 부모 revision과 일치한다. 항목 UPSERT 대상은 배열에 존재하고 DELETE 대상은 없어야 한다.
- 동일 부모 버전의 순서/관계/추가/제거를 한 트랜잭션에서 적용한다. 사라진 서버 항목은 삭제 표식으로 보존하고 로컬 전용 미전송 생성·수정 입력·원본 사본은 유지한다. 삭제된 항목 재노출, 다른 부모/계정, 중복 ID/entry_key, 같은 버전의 다른 내용은 거절한다.
- 항목 검증은 초기 사본 투영과 공유한다. 연결된 곡은 현재 계정의 서버 사본을 대조한다. 기존 헤더 단독 PLAYLIST payload는 기존 처리대로 유지한다. 물리 파일/사용자 데이터 삭제나 DB 마이그레이션 없음.
- 변경 파일: playlist_change_store.dart, change_feed_store.dart, change_feed_store_test.dart. 현재 모델 직접 검토에서 동일 버전 재수신과 내용 불일치 회귀 검증을 추가했다. 별도 에이전트 검수 아님.

실행: `flutter test --no-pub test/change_feed_store_test.dart test/snapshot_playlist_item_projection_test.dart test/recording_asset_projection_test.dart test/resync_integration_test.dart --reporter expanded` **83 PASS**. 변경3파일 `flutter analyze --no-pub` **No issues found**(최종 추가 회귀 테스트 포함). 마지막 항목 저장 실패 시 부모/앞 항목/커서 전체 롤백, 삭제 항목 재노출 거절, 미전송 입력 보존, owner/version 거절을 검증했다. 로그 `.local/workflow/p10-playlist-aggregate-reviewed.log`.

테스트 첫 실행의 Variable import 누락은 수정했다. 이후 샌드박스 실행이 출력 없이 정체해 해당 실행만 중단하고 기존 SDK 접근 가능한 실행으로 검증했다. 이것은 제품 논리 수정 실패가 아닌 실행 환경 문제다. 미실행 테스트를 통과로 기록하지 않았다.

이전 파일 세대 삭제 e214b3a5dc6caad4ff8639bcd3333a5b61a4d4c0 필수 CI4 PASS: CI36826555261/API36826555265/Idempotency36826555174/Workflow36826555184. 초기 목록 항목 c8f0f7205414c15d2aa9b3d1891596b54dd89355는 일반 푸시 완료, CI 확인 중. 이번 변경 전체 P10 완료/폰 실기 완료 아님. 사용자 직접 행동 없음. 다음은 남은 관계 엔티티 적용과 수신 연결 검증이다.

후속 통합 검증(같은 P10-06 작업): `flutter test --no-pub test/change_feed_receiver_test.dart --reporter expanded` **13 PASS**, 해당 파일 `flutter analyze --no-pub` **No issues found**. 수신 실행기→응답 해석→AccountStore→SQLite 목록 적용 후 계정 DB를 닫고 다시 열어 부모/항목 revision8·커서8을 확인했다. 중복 항목이 포함된 잘못된 응답은 부모/항목 없이 커서7을 유지함을 재개방 후 확인했다. transport는 합성 응답이며 실제 서버 목록 writer 발행/휴대폰 실기 검증으로 확대하지 않는다. 로그 `.local/workflow/p10-playlist-receiver.log`. 제품 구현7dda416 및 운영 문서7ccb4e8 로컬 커밋 완료. c8f0f72의 CI는 APK 빌드 단계 진행 중이며 통합 푸시 전 완료를 확인한다.

수신 통합 8d40ecc268e45fb1d1b60064931f513243104dd7의 필수 CI4 PASS 확인: CI36829102663/API36829102674/Idempotency36829102704/Workflow36829102668. 목록 수신 구현·Goal 운영 문서·수신기 통합 테스트가 포함된다. 이후 P10-09 새 변경 검증으로 확대하지 않는다.

<!-- runner-facts:P10-06:e2e3b5dbb65b46499d2ad3d142c538810bd53276 -->
### P10-06 실행기 검증 사실

- 대상 커밋: e2e3b5dbb65b46499d2ad3d142c538810bd53276
- 푸시 기준: fab47aa2bbb3d353056338f2e541e15124e1b44e
- 필수 CI 판정: PASS
- wire-tests: PASS / 테스트 61개
- store-tests: PASS / 테스트 64개
- receive-integration: PASS / 테스트 64개
- preservation-regression: PASS / 테스트 165개
- api-contract-regression: PASS
- analyze: PASS
- build-dev: PASS
- sources-check: PASS
- diff-check: PASS
- 검토 완료 기준: P10-06-A1, P10-06-A2, P10-06-A3, P10-06-A4, P10-06-A5, P10-06-A6, P10-06-A7, P10-06-A8, P10-06-A9
- 현재 모델 검토: 기존 두 지적의 수정과 회귀 검사 성공을 확인했습니다. 승인 계약·현재 diff·전체 지정 검사·중단 재개·데이터 보존을 대조했으며 남은 지적은 없습니다. 목록 writer·클라우드 전송·두 기기 종합 실기는 기존 후속 범위로 유지하고, 정상 완료 정리는 제어기에 인계합니다.
- 원시 근거: .local/workflow/runs/sequential/final-facts.json
