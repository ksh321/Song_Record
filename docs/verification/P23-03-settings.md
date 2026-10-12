# P23-03 개인화와 분류 관리

- 승인: P23-08까지 원수, 사용자 지정/관측 6.1 Sol medium. 원본 계획 p01012–p01014, D05·D06, 팔레트 AppAccent 8개를 대조. 기준 b148b695c982b98e6f0c5bbf9ad477421ecdff4a. 앞 번호 CI·폰 알림 처리 뒤 원수 begin.
- 강조색: 8개 그대로 사용. Android 전용 device_settings SharedPreferences에 허용 ID만 commit하고 성공 후 앱 테마를 변경한다. 초기 선택 블루, 회색 기본값은 별도 선택. 계정 DB·API·동기화·Song_Record 백업 대상이 아니며 Android 자동 백업도 기존 manifest에서 비활성. 시작 읽기 실패는 기존 테마 유지, 저장 실패도 기존 색 유지. 다른 계정 로그인·재시작 시 같은 설치본 기기 선택을 읽는다.
- 컨디션: 서버 고정 VERY_GOOD/GOOD/NORMAL/BAD 카탈로그만 표시. 사용자 생성·이름 수정·보관 API/버튼 없음. 녹음당 미선택/한 개, 태그 여러 개 정책 유지.
- 태그: ALL 상태와 페이지 커서로 기존 계정의 정의를 읽고 생성·이름 변경·보관을 기존 인증/멱등/버전 API에 연결. 보관은 신규 선택에서 숨기되 과거 녹음 관계와 이름을 변경하지 않는 기존 TagService/RecordingTag 계약을 유지. 이름은 기존 validateInput의 trim·Unicode 코드 포인트 1~50 검증, 초과를 자르지 않음. 서버 거절은 중복 이름·버전 안내, 불명확한 결과는 동일 body/operation으로 재확인.
- 서버 응답 뒤 기존 동기화를 깨우고 실제 현재 계정의 태그 메타데이터 버전·이름·보관 상태 일치를 확인하기 전까지 성공으로 표시하지 않는다. 미반영/로컬 충돌은 완료 대신 재확인. 동기화 연결이 없으면 편집 비활성. 전체 API 오류 본문·인증값 출력 없음.
- 계정 전환/늦은 응답을 차단하며 열린 확인 창도 닫는다. 반복 계정 알림이 여러 화면을 pop하지 않도록 dialogOpen을 먼저 해제하는 보완을 고정 화면에도 적용.
- 주요 파일: accent_preferences.dart/classification_screen.dart/settings_api.dart/song_record_app.dart/MainActivity.kt, classification_screen_test.dart, tool/classification_verification.dart.
- 영향 테스트 11개 PASS. 분석에서 확인한 미사용 import/스타일·LocalEntity import를 수정. 전체 일괄 검사/분석/APK/기존 서버 TagTests 진행. 원시 근거 .local/workflow/p23-03/ 보존.
- 기존 데이터 보존 근거: recording_edit_test의 renamed/archived 태그 이름 스냅샷 유지, recording_recovery_integration_test의 복수 태그와 컨디션 해제 시 파일 보존, 기존 TagService는 tag 정의만 UPDATE하고 recording_tag를 재작성하지 않음. 전체 검사에 포함.
- 설치본은 별도 합성 HTTP 태그이며 강조색만 검증 앱 기기 저장. 실제 운영 계정/녹음은 변경하지 않음. 완료 전 현재 모델 별도 diff 검토·설치본·대상 SHA CI 대조.
- 학습: 태그 정의 이름과 녹음의 당시 이름 스냅샷은 다른 데이터다. 보관은 정의 삭제/관계 삭제가 아니며 기기 강조색도 계정 동기화 데이터가 아니다.

## 실제 검증·검토 승인
- 일괄 checks.ps1 종료0 LOCAL_CHECKS_PASS. 전체 앱1182개 PASS(2:29), 분석 No issues, APK PASS, 기존 서버 TagTests5 PASS/skipped0. 최종 보완 후 영향15개·분석·APK 재검사 PASS.
- 검토 지적: 접수된 태그 변경보다 새 버전이 도착하면 옛 요청 무한 재시도 대신 최신 상태 재조회. root callback의 명시409 경로로 보완.
- SM_A546S install -r Success. 오렌지 저장 후 앱 프로세스 재시작 selected=true 유지(phone-accent-restart.xml). 합성 태그 입력 결과 그대로 표시·보관됨 표시, 보관 후 수정/보관 버튼 숨김(phone-renamed.xml/phone-archived.xml). 한글 IME가 실제 입력을 한글로 생성했으며 ASCII 입력 성공으로 추정하지 않았다. 실제 운영 계정/녹음/서버 DB 변경 없음.
- USER-094 ㄱ 회신 뒤 USB/device·잠금 해제 확인, 직접 할 일 제거. 알림 서버접수와 폰 수신 구분.
- 현재 모델 별도 검토 PASS: D05/D06·팔레트·원본 기준·실제 diff·계정/멱등/버전/기기 저장/이름 스냅샷·검사·설치본 대조. 소스 지문 review-approved.json. 대상 SHA CI 대기, 운영 서비스 통합 검증은 P25와 별도.
