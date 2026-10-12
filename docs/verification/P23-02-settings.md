# P23-02 용량과 고정 화면

- 승인: P23-08까지 원수, 사용자 지정/현재 관측 gpt-6.1-sol medium. 계획서 원본 p01009–p01011, 설계서 보관 정책과 기존 PinSlots 계약을 대조했다.
- 시작 기준: 18254c199aa82069f2c89c522651e06511a0d853. 앞 번호 완료 후 원수 begin 실행, 최초 사용량 값 유지.
- 실제 GET /v1/storage의 used/reserved/quota/trash/cleanup_pending/hold와 고정 사용·한도·대기를 표시한다. 포함·중복 관계를 설명하며 고정 해제·정리 대기를 즉시 공간 확보로 계산하지 않는다.
- 계정 범위 GET /v1/pins를 연결했다. 점유 슬롯만 반환하며 인증·계정 재검증·no-store를 적용하고 객체 키·파일 주소는 반환하지 않는다.
- 고정 신청: 현재 entitlement_revision. 교체·교체 취소·고정 해제: 표시된 슬롯 base_revision. 사용자 명시 확인 뒤에만 실행하며 취소는 명령을 보내지 않는다. 기존 보관 정책의 업로드·보호·실제 정리 작업을 변경하지 않는다.
- 결과 불명확 시 동일 body·Idempotency-Key로 재확인하고 새 명령을 막는다. 4xx 거절은 상태를 다시 읽도록 안내하며 자동으로 다른 녹음·버전·한도로 바꾸지 않는다. 계정 전환·늦은 응답은 폐기하고 열려 있는 선택/확인 창도 닫는다.
- 주요 파일: settings_api.dart, storage_screen.dart, song_record_app.dart, RetentionQueries.java, RetentionController.java, openapi.yaml; 영향/서버 검사와 합성 설치본 tool/storage_verification.dart.
- 검증: 영향 테스트 storage_screen_test.dart + settings_navigation_test.dart 10개 PASS. 첫 analyze에서 dynamic 비교 타입·스타일 오류를 확인해 수정한 뒤 재실행. 일괄 실행 .local/workflow/p23-02/checks.ps1 (전체 앱 검사·분석·APK·서버 build·계약), 실제 종료 결과는 아래에 추가한다.
- 별도 현재 모델 검토: 슬롯/계정/버전/확인/재시도 경계, 용량 중복, 기존 녹음·파일 보존과 실제 diff를 대조. 별도 에이전트 없음. UI 설치 검사는 합성 계정 HTTP로 수행하며 운영 사용자 파일은 변경하지 않는다.
- 대기: 전체 일괄 검사와 설치본 확인·대상 SHA 필수 CI. 완료 전 뒤 번호에 착수하지 않는다.
- 학습: 슬롯 해제는 보관 이유 하나의 변경이다. 파일의 다른 보관 이유·보호가 남으면 파일과 used_bytes는 유지된다. API 버전 확인은 다른 기기 변경을 덮어쓰지 않게 한다.

## 실제 검증·검토 승인
- 일괄 checks.ps1 종료 0 LOCAL_CHECKS_PASS. Flutter 전체 1177 PASS(2:31), analyze No issues, APK build PASS. 서버 테스트 {'tests': 725, 'failures': 0, 'errors': 0, 'skipped': 83} 및 build PASS, API 계약 검사 PASS. 로그 .local/workflow/p23-02/에 보존.
- SM_A546S 설치 갱신 성공. 합성 HTTP 설치본에서 교체 대기 취소 뒤 기존 고정 유지·대기1→0, 고정 해제 확인 취소는 기존 고정 유지, 명시 해제 뒤 고정1→0·사용량197 B 유지. 하단 버튼은 SafeArea 안에 표시·터치됨. XML 근거 phone-current-preserved.xml/phone-release-used-preserved.xml. 사용자 실기 회신을 대신한 실제 AI 설치본 검사이며 운영 계정 변경은 아님.
- 현재 모델 별도 검토 PASS: 실제 diff/완료 조건/실행 결과/계정과 버전/취소·재시도/데이터 보존 대조. 소스 지문 review-approved.json. 필수 CI 아직 대기.
