# P10-06j — 증분 변경 수신: 기존 실행 제어 연결

2026-10-01. 원본 P10-06 p00590~592와 기존 P10-03b 인증 후속 차단을 적용한 세부 작업.

ChangeFeedSyncBackend는 기존 SyncController가 호출하는 한 회차에서 증분 한 페이지를 먼저 받는다. 추가 페이지는 기존 제어기의 1초 후속 예약을 사용하고 자체 타이머/후속 요청을 생성하지 않는다. 따라잡은 경우만 송신한다. 인증 실패와 초기 사본 필요/커서 만료는 자동 후속과 송신을 막고, 임시 오류는 기존 복구 정책에 전달한다. 커서 만료의 실제 보존 재동기화는 P10-08 후속이며 완료로 표시하지 않는다. 새 정기 폴링 정책을 임의로 추가하지 않았다.

SnapshotSyncBackend는 초기 완료 후 내부 증분 상태 안내를 전달한다. 초기 완료를 근거로 증분 오류/대기를 빈 큐로 잘못 표시하지 않는다. ChangeFeedStepper 인터페이스는 현재 직접 실행/검증에 사용하며 에이전트 위임과 무관하다.

검증: flutter test --no-pub test/change_feed_sync_backend_test.dart test/snapshot_sync_backend_test.dart test/change_feed_receiver_test.dart test/sync_controller_test.dart --reporter expanded: **57 PASS**. 변경4파일 flutter analyze --no-pub: **No issues found**. 로그 .local/workflow/p10-06j-test.log.

현재 모델 별도 코드 검토에서 요청 1회, 후속 지연 우회 방지, 세션401/403, 임시 오류 복구, 외부 송신 인증 차단, 실제 SyncController 이탈/복귀 경합 및 Widget 상태 전달을 대조했다. 기존 테스트/CI를 약화하지 않았다. 변경은 새 backend와 receiver 인터페이스, snapshot 상태 전달, 관련 테스트4파일이다.

현재 실제 main 연결/새 APK 설치 전이다. 다음 P10-06 앱 구성 연결과 영향 검증을 수행한다. 기존 USER-024 확인은 e4adb7f에만 유지한다. 커밋은 Git history, CI는 후속 정확 SHA 결과로 기록한다. 전체 P10-06/만료 재동기화 완료 아님.
