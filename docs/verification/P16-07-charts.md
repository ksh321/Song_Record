# P16-07 — 차트 등록 맥락·지연 응답 (원수)

- 근거: 원본 계획 p00795~796·설계 p00162/167/1048/1056·D12·R007/R081/R089·V34/V40. TJ만 내 곡/목록 후보 선택, KY는 제목으로 실제 TJ 검색 후 사용자 선택. 대상 SearchIntent/목록/복귀 경로를 유지하고 취소 시 추가하지 않는다. 실제 플레이리스트 저장 구현은 기존 후속 P19 범위이며 여기서는 맥락/선택 계약을 전달한다.
- PopularChartScreen이 기존 KaraokeSearchScreen·SongRegistrationScreen·SongRegistrationDraft를 재사용한다. 원본 번호/곡명/가수/source_token 그대로 전달, 같은 제목 자동 연결/번호 변환 없음. sheet→검색→등록→저장 각 경계에서 요청 ID·brand/period·게시본 객체·원래 intent·계정/기기를 확인한다. 준비된 저장 재시도에서도 현재 맥락을 다시 확인해 이전 선택 저장을 차단한다.
- SongRecordApp 기존 인증/등록 준비 로더를 하나로 재사용, 개인 저장/동기화 동작 추가 변경 없음. chart API에 expires_at이 없으므로 KaraokeCandidate의 표시용 만료일은 nullable로 미확인 유지. 기존 검색 HTTP는 expires_at을 계속 엄격히 읽으며 등록 승인/24시간 검증은 기존 서버 SourceTokens/CandidateVerifier가 담당한다. 임의 만료일 생성/토큰 검증 약화 없음.
- 일괄 flutter test --no-pub --reporter expanded: 873 PASS. 신규5개는 TJ 증명·목록 맥락/취소, KY 실제 TJ 선택/복귀, 이전 sheet 차단, 실제 등록 폼 취소/저장, 실패 후 준비된 저장의 조건 변경 차단 확인. 기존 DTO/지연 응답·계정 무효화/검색/등록 테스트 포함.
- analyze 최초6 info는 함수 선언 형식·중괄호·명시 mounted 검사 요구이며 제품 테스트 실패와 분리. 최종 정정/영향 검사·APK·현재 모델 검토 결과는 뒤에 기록한다.
- 설치본: chart_registration_verification.dart, 기존 searchVerification 별도 ID·debug 한정. 합성 응답·메모리 저장 횟수만 표시하며 실제 개인 계정/서버/DB 저장 없음. 현재 USB 기기0, USER-066 준비 안내/폰 알림 서버 접수. 설치/실기 및 커밋·CI 대기, P16-08 미착수.
- 요청/실제 관측: gpt-6.1-sol/medium. 원수 처음 begin 및 현재 실행 경계 연결. 관련 학습: 등록 버튼 클릭 전에 확인하는 것만으로 충분하지 않으며 비동기 화면 복귀/저장 재시도 시에도 원래 선택 맥락을 대조해야 한다.

- 명령 환경 오류: 정정 명령의 cwd를 mobile로 지정하고 저장소 상대 경로를 사용해 파일 탐색 실패. 소스 수정이 없었으므로 동일6 lint 재검출/영향5 PASS·APK PASS는 정정 후 검증으로 간주하지 않았다. 저장소 경로에서 정정 뒤 최종 영향/분석/빌드를 별도로 실행했다. 코드 분석·수정·재검증 실패와 분리하며 검사를 약화하지 않는다.

## 최종 로컬 검사·현재 모델 검토
- 최종 영향5 PASS, analyze No issues found(3.8초), 최종 APK PASS(16.1초). 처음 전체873 PASS와 수정 영향 재검사로 최종 소스를 확인. Git 제외 로그/소스해시/APK해시 .local/workflow/p16-07 보존.
- 6.1 Sol/medium 현재 모델 별도 검토: 원본·D12·R007/R081/R089와 실제 diff·검사 대조 PASS. 기존 인증/번호 토큰 검증/개인 저장 계약 유지, 검색 expires_at 엄격 파싱 유지, chart 미제공 만료일 미추정. TJ 원본과 KY의 실제 TJ 선택을 분리, 원래 대상목록/복귀경로·화면 유지, 취소 추가0, 이전 응답/계정/기기/조건 변화 후 준비된 저장 차단. 독립 에이전트 검수 없음.
- 마지막 실제 USB 확인 기기0. USER-066 연결 대기이며 현재 설치본은 아직 P16-06. P16-07 필수 실기 전 푸시하지 않음. P16-08 미착수. 활성 제품 검사/빌드·CI 감시 없음. 미커밋5제품 파일과 검증 기록 보존.

## 설치본 확인
- 실제 R5CW618VA1M device·검증 소스/APK 해시 일치. install-r Success·MainActivity cold start Status ok. 전면 package com.ksh321.songrecord.searchverification, content-desc P16-07 차트 등록 검증·저장 횟수0·TJ00123 확인. USER-066 처리 완료, USER-0676개 결과 대기. 초기화/삭제 없음; 미커밋·CI전·P16-08미착수 유지.

## USER-067 기능 통과 및 하단 가림 수정
- 사용자 “다 통과”로 등록·KY→TJ·취소/횟수·지연 응답 기능 확인을 보존. 첨부2사진에서 TJ/KY 선택 시트 취소가 Android3버튼 탐색 영역에 가려짐 확인. 최종 가독성/배치 PASS로 처리하지 않는다.
- 원인 P16-07-SHEET-BOTTOM-INSET: 실제 Flutter SDK bottom_sheet.dart의 useSafeArea는 SafeArea(bottom:false)로 하단을 제외한다. 짧은 시트에서는 기존 스크롤로 해결되지 않음. 차트와 재사용 TJ검색 선택 시트 콘텐츠에 하단 SafeArea를 명시 추가, 긴 내용은 기존 ScrollView 유지. 기능/데이터 저장 계약 변경 없음. 첫 수정1회, 서로 다른 환경/lint 원인과 합산하지 않음.

- 수정 영향 검사10 PASS(차트선택6+기존검색4), 최종 analyze 문제0·수정 APK PASS(16.6초). 짧은 TJ/KY 차트·TJ/KY 검색 시트4조합에서64px 하단 탐색영역 밖의 취소 hit-test/버튼 하단 좌표 및 실제 취소 종료 확인. 신규 테스트 검색400ms debounce 준비 누락으로 검색 입력을 누른 오류는 별도 시험준비 원인으로 수정. 처음 차트2조합은 이미 통과, 제품 하단 수정 실패 횟수로 합산하지 않음. 진단을 위한 명령/출력 반복도 분석·수정·재검증3회 실패로 세지 않는다.
- 현재6.1 Sol/medium 별도 영향 검토 PASS: Flutter route 상단 safeArea와 내부 하단 safeArea가 영역을 분담, 하단 여백이 ScrollView 밖에 있어 짧은/긴내용 모두 탐색바에 가리지 않음. 등록 증명·맵핑·취소/저장 맥락·검색 행동 변경 없음. 최종 테스트·APK 해시 보존, 기존 기능 실기 통과 유지.
- 수정 APK 재설치 시 실제 adb device not found. USB가 분리되어 새 앱 설치/실제 폰 배치 재검수 미실행. USER-068 재연결만 필요; 기존6개 전체 실기 재요청 없음. P16-07 미커밋/CI전·P16-08미착수.

## 수정 설치본 최종 확인
- 수정 APK 해시 일치·install-r Success·MainActivity cold start Status ok. AI 실제폰 TJ/KY 선택 시트 취소 좌표[338,1991,478,2126]/[68,1991,207,2126], 터치 후 시트 종료·차트 복귀·합성 저장0 유지 PASS. UI 원본/스크린샷은 Git 제외 .local/workflow/p16-07/device-bottom-results.json 및 TJ/KY-fixed-sheet.png.
- 사용자 “이제 안 가린다”로 하단 가림 해소 확인. 기존 USER-067 기능6개 통과 + 수정 영향10개/분석0/빌드/별도 검토 + 실제 두 브랜드 취소 검증 대조 완료. USER-068 완료. 검사 제목/합성 데이터만 테스트 전용이고 수정한 선택 시트는 실제 앱 공유 차트/검색 컴포넌트다.
- 수정 후 실제 저장/개인 정보/DB 초기화 없음. P16-07 커밋·푸시·정확 SHA Flutter CI 후 완료 판정하며 P16-08은 아직 시작하지 않았다.

## 최종 완료
- 최종 SHA 73b1ca1dfe0db271973488e493e3b18e79e17537, 필수 CI 38024695024 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
