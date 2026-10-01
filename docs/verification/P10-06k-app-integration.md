# P10-06k — 증분 변경 수신: 앱 구성 연결

2026-10-01. 원본 P10-06의 실제 계정별 앱 실행 연결이다. main의 SnapshotSyncBackend 안에 ChangeFeedSyncBackend/ChangeFeedReceiver/HttpChangeFeedTransport를 넣어 초기 수신→증분 한 페이지→따라잡기 완료 시 송신 순서를 적용한다. 기존 SyncController의 전경 상태·단일 타이머 및 currentSession 검사를 유지한다. 수신 중 로그인 세션 객체·계정 저장소·ready 상태가 바뀌면 저장을 거절한다.

실제 검증: flutter test --no-pub test/change_feed_sync_backend_test.dart test/snapshot_sync_backend_test.dart test/sync_controller_test.dart test/auth_session_test.dart --reporter expanded **60 PASS**. main.dart analyze **No issues found**. 최초 import 정렬 권고를 보완했다. 로그 .local/workflow/p10-06k-integration.log.

현재 모델은 실제 main 초기화 순서, 계정 종료/인증 회복 시 객체 재생성, 증분 실패 시 송신 억제, 전경 후속 제어, 로그/화면에 비밀값을 넣지 않는 경로를 검토했다. 독립 에이전트 검수로 부르지 않는다.

dev APK를 기존 로컬 로그인 설정으로 빌드 중이다. 설정 값은 출력하지 않았고 RESET_AUTH_FOR_VERIFICATION은 false임을 확인했다. USB 대상 API는 127.0.0.1:8080이다. 새 설치 및 새 변경 화면 실기는 아직 대기이며 기존 USER-024 결과를 확대하지 않는다. 기존 앱 데이터/계정 저장소를 삭제하지 않는다.

전체 P10-06 완료 아님: 미구현 타입/영구 원장 적용과 P10-08 만료 커서 재동기화가 남았다. 현재 만료 상태는 입력을 보존하며 자동 후속을 멈추고 안내한다. 이 후속은 AI 작업이며 사용자에게 정책을 다시 선택시키지 않는다. 정확 커밋 CI와 APK/새 실기 결과는 후속 기록에서 확인한다.
