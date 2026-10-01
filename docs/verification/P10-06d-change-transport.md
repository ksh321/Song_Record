# P10-06d — 증분 변경 수신: 인증된 HTTP transport

2026-10-01. 원본 P10-06 p00590~592/R040, P10-06b 서버 계약과 P10-06c 앱 디코더의 후속 연결 범위로 세부 ID를 등록한다. 현재 설치 APK e4adb7f에는 포함되지 않는다.

고정 /v1/sync/changes 경로로 after_seq/limit만 전달한다. HTTPS 또는 명시적으로 허용한 로컬 개발 주소만 사용하며 서버가 준 URL을 사용하지 않는다. Bearer/X-Device-Id를 넣기 전후 계정 fence를 검사한다. 자동 redirect/retry 없음. 401/403/409 응답과 중단 시 이미 받은 상태를 보존하므로 수신기가 인증 차단과 CURSOR_EXPIRED를 구별할 수 있다. 기본20초·최대128MiB의 클라이언트 응답 방어 한도가 있으며 이 값은 서버 보관 정책이 아니다. 부분 응답/잘못된 UTF8를 성공으로 반환하지 않는다. DB/커서 수정 없음.

실제 로컬 HttpServer를 사용한 검사: 고정 GET/Long 최대 순번/정확 헤더/빈 body, 302·401·403·409 한 번씩만 요청, 응답 지연 중 계정 교체, 최초 stale fence 전송0회, 403 header 후 body 지연의 단일 시도/시간 제한, 응답 크기 및 UTF8 실패, 안전하지 않은 주소/파라미터 거절.

실행:
- dart format lib/core/sync/change_feed_transport.dart test/change_feed_transport_test.dart
- flutter test --no-pub test/change_feed_transport_test.dart test/change_feed_response_test.dart --reporter expanded: **15 PASS**(transport7+decoder8).
- flutter analyze --no-pub lib/core/sync/change_feed_transport.dart test/change_feed_transport_test.dart: **No issues found**.
- 기록/선택기 영향 확인 python -m unittest discover -s tools/tests -p test_work_selection.py: **16 PASS**.

현재 모델 별도 코드 검토: 고정 경로/credential 전달 대상, 계정 교체 후 응답 거절, 자동 후속 요청 없음, 모든 종료 경로의 HttpClient.close(force:true), 상태 보존을 실제 코드/테스트와 대조했다. 비밀값/실기 로그를 테스트에 넣지 않았다. 모델·속도 상향 적용 주장 없음. 코드 커밋 후 CI는 통합 SHA로 확인한다.

남은 P10-06: 실제 저장소 원자 적용과 커서 전진, 초안/base_payload 및 파일 보존, 초기 사본과의 연결, 수신 실행기와 앱 연결. transport 성공을 전체 수신 완료로 기록하지 않는다.
