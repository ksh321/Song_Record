# P10-05n — 일관된 초기 스냅샷: 앱 전경 수신 연결

2026-10-01. 계획서 P10-05/D09의 수신 실행기를 실제 계정별 앱 진입점에 연결하는 세부 ID다.

main에서 SnapshotSyncBackend/SnapshotReceiver/HttpSnapshotTransport를 기존 RepositorySyncBackend 앞에 연결한다. 계정별 컨트롤러, 전경·로그인 허용 검사, 실제 계정 저장소 fence를 유지한다. 초기 수신 완료 후 기존 송신이 진행된다. 새 UUID v4는 Random.secure로 생성하고 수신 실행기가 최초 HTTP 이전 디스크에 저장해 재시도에 재사용한다.

SyncStatusSource를 통해 초기 수신·서버 준비·인증 중단 문구를 기존 동기화 화면에 표시한다. 수신 중/인증 중단을 빈 큐 완료 문구로 표시하지 않는다. 비밀값/원문 오류/계정 식별자를 화면에 넣지 않는다. 로그인 상태 회복은 기존 계정 열기 흐름에서 새 backend를 구성한다.

검증: flutter test --no-pub test/snapshot_sync_backend_test.dart test/sync_controller_test.dart test/snapshot_receiver_test.dart --reporter expanded **44 PASS**. 관련6파일 analyze **No issues found**. import 정렬 권고를 보완했다. 코드 검토에서 초기화 순서, 계정별 수명, 전경 이탈 뒤 세션 검사, 기존 단일 타이머, 수신/인증 상태의 빈 화면 오표시 방지를 대조했다. 현재 모델 직접 검토이며 외부 위임 없음.

로그 .local/workflow/p10-05n-app-test.log. APK/실기 및 정확 SHA CI는 아직 대기다. 기존 폰 결과를 새 변경 검증으로 확대하지 않는다. 기존 편집 사본을 자동 덮어쓰거나 미전송 초안을 병합하지 않으며 m의 읽기 기반과 후속 충돌/증분 연결은 별도 범위다. 전체 P10-05 완료 아님.

실제 dev APK 빌드 종료0. 코드 e4adb7fc68cc445b05bd6f4fe046d5b5e840a842 사본 고정, 설치 전. USB0으로 USER-022 연결 요청. Docker 엔진/API 미실행을 확인하고 기존 Docker Desktop 시작 요청; DB/볼륨 삭제 없음.

환경 복구: Docker 런타임 소켓 OS 접근 오류로 시작 실패. 정상 종료/보존 이동/빈 소켓 정리 시도도 실패했고 데이터 삭제 성공 없음. 사용자 USER-023 Windows 재시작 후 엔진 실행 확인 대기. 소프트웨어 논리 실패 횟수와 구분. USER-022 USB 연결 대기. ntfy 두 요청 서버 접수, 실제 수신 미확인.

통합 e4adb7fc68cc445b05bd6f4fe046d5b5e840a842 필수4 CI PASS: CI36796712600, API contract36796712573, Idempotency MySQL36796712623, Development workflow36796712619. 폰 검증은 여전히 대기.

2026-10-01 재시작 회신 후 환경 복구 확인: 기존/격리 DB healthy, USB device1대, API health UP. 고정 e4adb7f APK의 SHA256 일치 확인 후 adb install -r Success. USB reverse8080 연결. 사용자 실기는 USER-024로 별도 요청, ntfy 서버 접수이며 수신/실기 결과는 미확인. 과거 USB0/설치 전/엔진 차단은 당시 기록이다.

자동 준비 추가 확인: e4adb7f 앱의 실제 resolve-activity 결과로 실행, 종료0 및 프로세스 유지. 해당 PID의 최근500줄 로그를 .local에만 저장했고 FATAL EXCEPTION/Unhandled Exception 각각0. 읽기 전용 DB 쿼리에서 최근10분 SYNC 스냅샷 READY1개 확인. 서버 준비 상태이며 앱 적용 완료/사용자 화면·홈 복귀 성공으로 확대하지 않음. USER-024 반복 알림 없음.

USER-024 회신 ‘오류 없음’ 수신. e4adb7f 새 앱 연결의 지정 실기 요청에 대한 사용자 확인으로 기록한다. 실제 세부 문구/수신 중 이탈 확인 여부는 미제공이며 만들어 쓰지 않는다. 추가 실기 반복 요청 없음. 기존 자동44 PASS/CI4 PASS와 합쳐 n 연결 범위 검증 완료. 초기 사본의 전체 업무 조회 투영 등 P10-05 후속 범위는 별도이며 전체 P10-05 완료로 확대하지 않는다.
