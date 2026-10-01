# P10-05n — 일관된 초기 스냅샷: 앱 전경 수신 연결

2026-10-01. 계획서 P10-05/D09의 수신 실행기를 실제 계정별 앱 진입점에 연결하는 세부 ID다.

main에서 SnapshotSyncBackend/SnapshotReceiver/HttpSnapshotTransport를 기존 RepositorySyncBackend 앞에 연결한다. 계정별 컨트롤러, 전경·로그인 허용 검사, 실제 계정 저장소 fence를 유지한다. 초기 수신 완료 후 기존 송신이 진행된다. 새 UUID v4는 Random.secure로 생성하고 수신 실행기가 최초 HTTP 이전 디스크에 저장해 재시도에 재사용한다.

SyncStatusSource를 통해 초기 수신·서버 준비·인증 중단 문구를 기존 동기화 화면에 표시한다. 수신 중/인증 중단을 빈 큐 완료 문구로 표시하지 않는다. 비밀값/원문 오류/계정 식별자를 화면에 넣지 않는다. 로그인 상태 회복은 기존 계정 열기 흐름에서 새 backend를 구성한다.

검증: flutter test --no-pub test/snapshot_sync_backend_test.dart test/sync_controller_test.dart test/snapshot_receiver_test.dart --reporter expanded **44 PASS**. 관련6파일 analyze **No issues found**. import 정렬 권고를 보완했다. 코드 검토에서 초기화 순서, 계정별 수명, 전경 이탈 뒤 세션 검사, 기존 단일 타이머, 수신/인증 상태의 빈 화면 오표시 방지를 대조했다. 현재 모델 직접 검토이며 외부 위임 없음.

로그 .local/workflow/p10-05n-app-test.log. APK/실기 및 정확 SHA CI는 아직 대기다. 기존 폰 결과를 새 변경 검증으로 확대하지 않는다. 기존 편집 사본을 자동 덮어쓰거나 미전송 초안을 병합하지 않으며 m의 읽기 기반과 후속 충돌/증분 연결은 별도 범위다. 전체 P10-05 완료 아님.
