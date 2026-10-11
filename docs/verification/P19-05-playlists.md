# P19-05 등록 여부별 표시

- P19-09까지 원수 승인, 요청/관측 gpt-6.1-sol/medium. 기준 5d4b6d7515cbaf3ba9b7eaa8388f22eaac51fedf, 원수 begin 측정 확인.
- 원본 계획서 v1.0 문단881~883: 등록곡은 Song 정보, 미등록 TJ 후보는 곡명·가수만. 곡 수정은 연결 목록에 반영하고 후보에 개인 키·티어·버전을 붙이지 않는다. 요구사항 R080/C05·V27/V37.
- 설계서 v1.11 문단681~683과 보존 HTML·UI_REFERENCE·팔레트의 목록 표시 규칙 적용. 기존 SongRow/MySong 표시 도구 재사용, 원본 보존.
- 실제 화면 변경이 있어 설치본 확인 필요. USER-085 USB 연결만 사용자 행동으로 준비·알림, 연결 대기 중 구현/검사 계속. 통과 결과를 미리 기록하지 않는다.

## 구현·검사 준비
- PlaylistDetailScreen은 기존 SongRow/MySong을 재사용한다. 등록 항목은 현재 ACTIVE Song, 미등록 TJ는 candidate_snapshot의 곡명·가수를 표시한다. 개인 키·티어·버전은 후보에 전달하지 않는다. 연결 Song이 없으면 후보로 되돌려 표시하지 않는다.


## 실제 검증·현재 모델 검토
- 전체 Flutter test 971개 PASS(123.45초). 검증용 Song PATCH Map 키 타입 분석 지적을 수정한 뒤 표시·추가 영향6개 PASS, analyze 0문제, searchVerification APK 빌드 PASS, diff --check PASS. 검사 로그는 Git 제외 .local/workflow/p19-05에 보존한다.
- 실기 SM_A546S/R5CW618VA1M: 기존 데이터 유지 install -r 성공. 초기 TJ 등록곡의 일반 반주·미정 키/티어 및 미등록 TJ 후보의 곡명·가수·내 곡 미등록 확인. ‘곡 정보 수정’ 실제 로컬 saveCheckedEdit 이후 새로고침 없이 수정 반영 곡/수정 가수·LIVE/티어 A/남 +2 확인. 후보에는 동일 정보가 붙지 않음. force-stop/재시작 후 같은 표시 확인(ui-initial-ready/edited/restarted.xml). 검증 앱의 별도 합성 계정이며 운영 서버 검증으로 확대하지 않는다.
- 현재 모델 gpt-6.1-sol/medium이 완료 조건·실제 diff·검사·설치본을 별도 검토. raw SQLite 갱신 특성을 고려한 1초 로컬 읽기, 내용이 바뀔 때만 재표시, 중복 읽기 방지, dispose 타이머 해제, 계정 lease 실패 시 이전 정보 제거 확인. 등록 Song 부재 시 후보로 복귀하지 않음. 후보 정보는 기존 공통 SongRow의 playlist 표시 규칙만 사용한다.
- 테스트 가상 시간과 DB 비동기 대기는 실제 시간 구간으로 분리해 실제 DB·동기화 검증을 유지. 가짜 상태 대체 제안은 자동 승인 검토에서 거절돼 미적용. 별개 기대 표시 지적은 공통 행의 실제 티어/키 표시와 대조해 수정. 서로 다른 원인을 합산하지 않는다.
- 변경 파일: playlist_detail_screen.dart, playlist_addition_fixture.dart, playlist_display_fixture.dart, playlist_display_verification.dart, playlist_display_test.dart. 원본 문서·개인 데이터 보존. R080/C05 V27/V37, 새 모델 호출 없음.
- 로컬·실기 완료. 최종 SHA의 영향 Flutter CI 대기 후 P19-06.
