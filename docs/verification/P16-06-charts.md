# P16-06 — 브랜드·기간 인기곡 화면 (D12, 원수)

- R087·D12: 실제 AppShell 인기 차트 탭에 PopularChartScreen 연결. TJ/금영·일간/주간/월간, 기본 TJ/월간, 브랜드 변경 시 기간 유지. 원본 HTML·UI_REFERENCE·팔레트의 공통 SongRow/표면/간격/타이포를 재사용하되 연월·최종월 배지는 D12로 대체했다.
- PublishedChart DTO는 기대 brand/period/provider/source_url·timezone·revision·stale·전체 항목 순서/번호 중복/필수값/선행0·TJ source token/KY null을 검증한다. HTTP는 현재 서버 /v1/charts/popular만 요청, HTTPS 또는 debug localhost, redirect 금지·2MB/전체5초 제한. 인증 세션을 요청 전후 대조하고 계정/기기 변경 시 요청 세대와 표시 자료를 비운다.
- 화면은 제공자 기준 기간/정확 집계 날짜 미제공, MANANA 실제 scope URL·서버 수집 시각·revision 및 stale 이전 정상 자료 안내를 표시한다. 자료 없음과 연결 오류를 구분해 같은 조건으로 재시도하며 다른 기간 자료로 대체하지 않는다. 개인 키/티어/버전 표시나 개인 동기화 저장은 추가하지 않았다. 곡 선택·등록 맥락은 다음 P16-07에서 연결한다.
- 로컬 일괄 flutter test --no-pub --reporter expanded: 기존 및 HTTP862 PASS, 신규 화면 테스트 파일은 SDK 테스트 API setPhysicalSize 미존재로 로드 실패1. 실제 SDK physicalSize setter로 수정. 5개 신규 lint 형식 문제는 해당4파일만 자동 정정했다.
- 영향 재검사 flutter test --no-pub test/popular_chart_test.dart test/popular_chart_http_test.dart --reporter expanded: 8 PASS(6신규 화면/데이터·2HTTP 중복). 따라서 고유 검사868 범위 확인. 분석 flutter analyze --no-pub: No issues found. 최종 flutter build apk --debug --flavor searchVerification -t tool/chart_verification.dart --no-pub PASS. 마지막 소스의 APK 해시는 Git 제외 .local/workflow/p16-06/apk-sha256.txt.
- 현재 요청/실제 관측6.1 Sol/medium 직접 별도 검토: D12·실제 변경·검사 대조, 범위 유지·자료 혼합 방지·계정 변경 무효화·no external call·원본 토큰 및 metadata·기존 탭/녹음 미변경·큰 글꼴/320x640 PASS 확인. 린트/SDK 테스트 오류와 제품 논리 실패를 분리, 테스트 약화 없음. 검토 PASS.
- 폰 R5CW618VA1M device 확인, 기존 searchVerification 별도 ID에 install -r Success; MainActivity 시작 Status ok. 앱/DB 삭제나 초기화 없음. 실제 uiautomator 전면은 com.android.systemui로 앱 화면 표시 아직 미확인. 사용자 잠금 해제 후 실제 화면 검사 필요; 설치를 실기 통과로 처리하지 않는다.
- 검증 앱은 개인 계정/서버 연결 없음·합성 응답으로 실제 화면4모드를 제공. 운영 출처/실자료/저장 허용 승인으로 확대하지 않는다. USER-065 실기 결과 대기, P16-06 미커밋·미푸시·CI 미실행. P16-07~08 미착수.
- 변경: features/charts/popular_chart.dart, popular_chart_http.dart, popular_chart_screen.dart; app/app_shell.dart, song_record_app.dart; test/popular_chart_test.dart, popular_chart_http_test.dart; tool/chart_verification.dart.
- 학습: 선택 조건·요청 세대·로그인 계정을 함께 확인해야 늦은 네트워크 응답이 새 화면에 섞이지 않는다. 공용 원본 데이터와 개인 곡 정보를 구분한다.

## 사용자 실기 확인
- USER-065 사용자 “모두 통과”: 안내된6개 정상/6조합/출처/이전자료/없음·오류/가독성 설치본 검사 PASS. 검증한 소스 변경 없음. 커밋·정확 SHA Flutter CI 진행.
