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
