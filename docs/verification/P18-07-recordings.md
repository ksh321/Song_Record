# P18-07 — 녹음 행과 정렬

- 원수 요청 gpt-6.1-sol/medium. 원본 계획 v1.0 p852–854, 설계 v1.11 p220·241, UI_REFERENCE 정렬·목록, HTML 녹음 목록과 palette 연결 확인.
- 목록은 당시 제목·가수·일반 반주/MR/LIVE·녹음 당시 시간대 날짜·공통 키 표시·녹음 티어·기기와 서버 파일 상태를 표시. 기존 검증된 file status 서비스를 재사용하고 파일 없는 SAVED metadata도 유지.
- 작은 정렬 버튼과 체크 표시 바텀시트. 최신·오래된·곡명·티어순, 티어 S→A→B→C→D→미정·동률 실제 시각 최신순·최종 ID순. 목록 표시/정렬만 바꾸고 metadata·파일·전송 큐 쓰기 없음.
- 현재 모델 별도 검토: 원본 완료 조건·diff·당시 스냅샷·실제 시각과 표시 시간대 구분·파일 없음/확인 불가 구분·계정 fencing 대조. 파일 상태 조회 이후에도 계정 lease 확인 추가. 전체 metadata 로드가 유지되며 앞 페이지 파일 필터는 적용하지 않음. P18-08 필터와 P18-09 집계는 다음 번호에서 연결.
- 변경 파일: recording_list.dart, recording_workspace.dart, recording_verification.dart, recording_list_test.dart.
- 최종 analyze0(58.9초), 영향10 PASS(2초). 타입/import 지적은 직접 수정. 전체·빌드·실기·커밋·CI는 아직 진행 중.

## 검사·설치본 PASS
- 전체948 PASS(1분41초), APK 빌드22.1초. 로그 .local/workflow/p18-07/.
- SM_A546S install-r Success 후 실제 원본 녹음 행에 제목·가수·LIVE·2026/10/10·원키·S·기기 파일 있음/서버 확인 불가 표시. 정렬 네 항목이 시스템 내비게이션 위에 표시, 오래된/티어/곡명 선택과 행 상세 진입 확인. 폰의 실제 녹음은 1개이며 여러 행 순서/동률·파일 없는 행은 로컬 테스트 근거로 구분. 기존 녹음 반복 없음.
- 커밋·푸시·필수 CI는 다음 단계.
