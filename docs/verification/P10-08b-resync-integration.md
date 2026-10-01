# P10-08b — 만료 커서 재동기화: 응답과 앱 실행 제어 연결

2026-10-01. P10-08 p00596~598와 P10-08a의 보존 요청 저장을 실제 만료 응답/앱 구성에 연결한다. 전체 P10-06 완료를 가정하지 않으며 이미 검증된 수신·계정 저장 기반의 후속 컴포넌트다.

ChangeFeedReceiver는 CURSOR_EXPIRED 응답에서 관측한 토큰/커서가 아직 현재일 때만 새 요청 UUID를 저장한다. 다른 실행이 기준을 바꿨다면 재시도 상태로 돌아가 오래된 응답으로 새 기준을 무효화하지 않는다. 요청 저장 성공 시 초기 사본 필요 상태를 반환한다. 기존 SnapshotSyncBackend는 SnapshotRestartSource를 통해 초기 수신으로 재진입하며 기존 예약 시각을 넘겨받아 조기 wake로 지연을 우회하지 않는다. 새 사본 검증/교체 후 증분을 다시 받아 따라잡은 뒤만 송신한다. 자체 타이머는 없다.

실제 main에서 보존 재동기화 기능을 켰다. 인증 차단과 전경·계정 세션 검사는 유지하며, 기존 데이터/미전송 큐/파일을 지우지 않는다. 새 사본을 기다리는 동안 예전 기준 사본 읽기는 가능하다. 새로운 버전 APK를 아직 설치하지 않았으므로 USER-025의 c7df3fd 확인을 확대하지 않는다.

검증:
- flutter test --no-pub test/change_feed_receiver_test.dart test/change_feed_sync_backend_test.dart test/snapshot_sync_backend_test.dart test/snapshot_download_store_test.dart test/sync_controller_test.dart --reporter expanded: **73 PASS**.
- flutter test --no-pub test/resync_integration_test.dart --reporter expanded: **1 PASS** 추가 통합 검증.
- 변경6파일 및 추가 통합 테스트 파일 analyze: **No issues found**. import 순서/테스트 if 블록 지적을 보완한 뒤 실제 재확인했다.
- 통합은 격리 실제 AccountStore, 실제 초기/증분 수신기·backend, 합성 HTTP 응답과 공유 hash fixture를 사용했다. 만료 응답 뒤 기존 사본이 유지되는 동안19종 페이지가 검증되고, 새 token으로 교체한 뒤 증분 재개/송신1회가 일어났다. 비snapshot/비cursor 테이블 전체 동일 및 합성4바이트 파일 동일을 확인했다. 실제 네트워크/폰 실기로 확대하지 않는다.
- 로그 .local/workflow/p10-08b-test.log, p10-08b-integration.log.

현재 모델 검토에서 CAS 실패, 계정 fence, 요청 재사용, 초기 다운로드 만료 후 flag 유지, 후속 지연/송신 억제 및 실제 전체 순서를 대조했다. 영구 삭제 대상의 모든 관계 투영/미전송 충돌 재적용(P10-07/P10-09)까지 완료가 아니다. 정확 SHA CI는 후속 통합 기록에서 확인한다.
