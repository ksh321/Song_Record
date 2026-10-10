# P15-08 — 검색·등록 경계 종합 검증 (원수)

## 원본·범위
- 코드구현계획서 v1.0 실제 Word 768~770, R013~R015/R081/R083~R085/R089, V31/V32/V34/V35/V40.
- 같은 번호 재사용·기존 편집 보존, 다른 번호 분리, KY/위조 거절, 취소 무생성, 정상 검색 없음/장애 구분, 최신 요청 응답을 확인한다. P19 목록 API는 이번 범위로 앞당기지 않는다.
- P15-07 완료 SHA 5b5abace81c7145f482704584bf179068eb5f633, 필수 CI PASS 및 완료 알림 서버 접수 확인 후 원수 finish07/begin08. 요청 6.1 Sol/medium 유지. 추가 모델 호출 없음.

## 변경
- services/api/.../auth/KaraokeRegistrationTests.java: 실제 SourceTokens AES-GCM·LiveCandidates·TjCandidates·SongCreation·계정/중복 요청/변경 로그를 격리 H2 fixture에서 연결했다. 외부 제공자 응답만 통제하며 서비스는 실제 구현을 사용한다.
- apps/mobile/tool/search_verification.dart: verification debug 전용 설치본. 실제 검색/등록 화면과 SQLite를 사용하되 외부 응답·첫 저장 실패만 통제한다. 별도 p15-08-search 저장소·실행마다 신규 합성 계정으로 이전 검사/개인 앱 데이터를 보존한다. 서버·개인 계정·키는 사용하지 않는다.

## 현재 근거
- 최초 새 서버 통합 4개 PASS. 검토 후 실패 코드별 기대값을 강화했다.
- 전체 API643개: 563 성공/80 MySQL 제외/실패0. bootJar PASS. 제외80은 통과로 계산하지 않으며 필요한 실제 MySQL CI는 푸시 후 확인한다.
- 정상 같은 번호는 기존 canonical ID·편집·메모와 change_log 수를 보존, 제목이 같은 다른 번호는 별도 곡/출처, KY와 변조 증명은 모든 메타데이터/receipt 무생성, 만료+장애는 동일 원문/operation 재시도 후 원자 생성 및 replay, 번호 선행0 바꾸기 거절을 실제 서비스에서 검증했다.
- 모바일 기존 karaoke_search/karaoke_ky_flow/song_registration 검사에서 400ms 입력 지연·늦은 성공/실패 무시·브랜드/조건/계정 변경 무효화·TJ 재선택 맥락·취소·MANUAL 차단·오프라인 저장/재개·불변 요청 재시도를 확인한다.
- 현재 일괄 검사: .local/workflow/p15-08/checks.ps1. 모바일 전체/분석/설치본 최종 결과는 실제 완료 뒤 추가한다.

## 실기·다음
- 원본 서버와 화면 경계를 나눠 검증한다. 폰의 합성 응답을 실제 Manana 조회 또는 실제 계정의 서버 등록으로 주장하지 않는다. 외부 어댑터 실제 조회는 P15-01의 기존 근거, 외부 장애 분류는 LiveCandidatesTests의 실제 ProviderFailure 연결을 유지한다.
- 현재 USB 미연결. USER-060 연결 요청을 대화와 폰으로 안내했으며, 연결 확인 후 AI가 앱 데이터 삭제 없이 별도 앱을 설치·실행하고 정확한 6개 조작을 안내한다.
- 필수 실기 대기 동안 커밋·푸시·완료 판정 및 P16 착수는 하지 않는다. 가능한 AI 검사/준비는 모두 진행한다.

## 최종 로컬·검토 결과 / 설치 대기
- 일괄 로컬 검사 PASS: 서버643개(563 성공/80 MySQL 제외) 및 bootJar, 모바일860개 전체 PASS, 분석 지적0, 별도 verification debug APK 생성(46.9초).
- 현재 모델 별도 검토: 실제 완료 기준과 diff/실행 결과 대조. V31의 두 번째 요청은 가수 표기와 버전도 다르게 보강했다. 영향 통합4개 재검사 PASS. 제품 코드·기존 기대값/검사 삭제·약화 없음.
- git diff --check 오류0(기존 LF/CRLF 안내만). 설치본은 앱 데이터 보존용 별도 applicationId com.ksh321.songrecord.verification이며 APK 파일과 해시는 로컬 재개 기록에 저장한다.
- 2026-10-10 실제 ADB devices 연결0. USER-060 USB 요청과 폰 알림 서버 접수, 폰 수신 미확인. 앱 설치/실기 미실행, 커밋/푸시/CI 미실행. 현재 HEAD 5b5abace81c7145f482704584bf179068eb5f633.
- AI 가능한 준비 완료. 사용자 연결 회신 후 실제 연결 확인 → 기존 도구로 adb install -r 및 별도 앱 실행 → 실제 화면의 6개 조작 안내/필수 회신 확인 → 커밋·푸시·필수 CI. 이후 P16-01부터 순차 진행.
- 동작을 합성한 실기 응답을 실제 제공자 데이터로 해석하지 않는다. 같은/다른 번호의 서버 통합은 PC 근거, 취소/금영/직접 등록/장애/지연/저장 실패의 화면은 폰 근거로 나눠 기록한다.

- 실제 USB SM-A546S device 확인, 원수 resume 연결. 기존 verification APK install -r은 INSTALL_FAILED_UPDATE_INCOMPATIBLE로 거절(기존 서명 차이; 환경 실패, 코드 실패 카운터와 분리). 삭제/초기화/기존 서명 우회 없이 전용 searchVerification debug flavor와 com.ksh321.songrecord.searchverification ID를 추가해 별도 설치한다. 기존 APK/검사 이력 보존.

- searchVerification 분석 지적0·APK build62.3초 PASS. 실제 SM-A546S에 install -r Success, 전용 MainActivity 실행 및 준비 완료·검사1~6 화면 확인. 기존 앱 삭제/DB 초기화 없음. USER-060 해소, USER-061 6개 실기 회신 대기. 실기·커밋·CI는 미완료 유지.

## 설치본 사용자 확인
- SM-A546S 별도 searchVerification 설치본의 안내한 검사1~6 모두 성공이라는 2026-10-10 사용자 명시 회신. 취소0·금영 재선택/취소0·MANUAL1·장애1유지·지연1유지·실패입력보존/같은명령재시도2 범위 확인. 첨부2장의 검사2 TJ/KY 화면은 보조 근거이며 사진만으로 전체 검사를 추정하지 않는다. USER-061 처리 완료, 직접 할 일0건.
- 실제 server 경계4개·원본 V31/V32/V34/V35/V40·모바일860 및 기존 동기화 완료 근거·설치본6개·현재 모델 검토를 대조. 새 전용 flavor는 기존 설치본 서명/데이터 보존 목적이며 분석0·APK PASS. 관련 검증 앱·Gradle flavor diff 재검토 지적 없음. 필요한 CI 통과 전 완료 판정은 보류한다.
