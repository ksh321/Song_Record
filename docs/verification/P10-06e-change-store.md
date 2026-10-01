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
