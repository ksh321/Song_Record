# P17-01 — 내 곡 로컬 조회

## 범위·근거
- 사용자 P17-01~08 원수 실행 승인, 요청/실제 관측 gpt-6.1-sol/medium. 최초 사용량/시간 begin 및 실제 실행 ID 연결. 첫 기준 HEAD/원격 조회 0e76d24d81b211c9c55cdd2968f1045b22c7af42. P17-02~08은 미착수.
- 원본 계획서 XML p00805~p00807, 원본 설계서 2.1.1 및 R020/V46/C03 대조. UI_REFERENCE·원본 HTML 내 곡 검색/빈 결과·팔레트 확인, 기존 SongRow/ContentState/테마 사용.
- 실제 무료 서비스 배포 목표 유지. P16 실데이터 운영 연결/검증 남은 준비를 보존하며 합성 검사를 운영 배포 완료로 확대하지 않는다.

## 변경
- AccountStore.readActiveSongs/watchActiveSongs: 기존 계정 lease·직렬 실행 보호로 metadata_copies 읽기. 소유 계정/SONG/tombstone0·lifecycle ACTIVE·canonical source 제외. 미전송 local_payload를 server_payload보다 우선하고 identity/소유권 오류를 거절한다. 스냅샷/증분 수신의 기존 metadata projection도 같은 조회로 표시한다.
- 기존 raw SQLite 쓰기는 Drift watch invalidation을 발생시키지 않아 현재 계정 로컬 DB를 1초 간격으로 확인, 내용이 달라질 때만 stream에 전달한다. 서버/Manana 호출·DB schema 수정 없음. 원본/녹음 파일/미전송 큐 변경 없음. LocalRepository는 동일 lease 스트림을 노출한다.
- MySong/MySongsScreen: 제목·가수 부분 일치, 앞뒤 공백·영문 대소문자 정리, 빈 검색 전체. 오류/읽기 대기/빈 결과를 구분한다. 외부 결과는 섞지 않고 새 곡 찾기는 기존 발견 시트를 통한 별도 사용자 동작이다. 공통 곡 행은 일반 반주/버전·키/티어 표시와 목록 TJ 번호 숨김 규칙 재사용.
- SongRecordApp/AppShell의 실제 내 곡 탭 연결. 현재 auth ready 및 repository 계정 일치 확인, 계정/기기/phase 변경 시 이전 자료/검색을 즉시 제거하고 구독을 취소한다. 요청 generation으로 뒤늦은 이전 스트림 데이터/오류를 무시한다.
- 아직 곡 상세/정렬/편집/목록 추가는 후속 원본 P17 번호에서 구현한다. 기존 인증 복원/LoginGate는 수정하지 않았다. 이번 오프라인 근거는 열린 현재 계정의 로컬 조회/입력이며 오프라인 cold-start 인증 복원까지 검증했다고 주장하지 않는다. 최종 실제 앱 통합/배포 검수에서 이 경로도 별도 대조해야 한다.

## 검사와 문제별 기록
- 최초 명령의 저장소 cwd/상대 로그 경로 오류는 실행 준비 문제이며 제품 검사가 실행된 것으로 세지 않는다.
- P17-01-COMPONENT-CALL: SongRow.registered의 named 인자를 positional로 호출한 컴파일 오류. 수정1회로 song: 인자를 사용. 최초 일괄 실행의 컴파일 실패4파일/869PASS는 최종 통과가 아니다.
- 최초 analyze의 검증 도구 if중괄호 info는 별도 lint 원인으로 수정1회.
- P17-01-TEST-CLOSE: 새 widget test 정리에서 fake async 스트림 close 대기. 검사 assertions를 유지하고 tester.runAsync 정리로 수정1회. 중단한 일괄 실행은 완료로 합산하지 않는다.
- P17-01-ORPHAN-DLL: 중단된 테스트 자식 flutter_tester가 sqlite3.dll을 잡아 Flutter 재실행 실패. 실제 PID/부모 종료/이 저장소 unit_test_assets 경로를 확인한 해당 자식만 종료. SDK 권한·DB/앱 초기화로 우회하지 않았다. 코드 수정 실패 횟수와 분리.
- 수정 후 영향4 PASS(실제 SQLite ACTIVE/휴지통/미등록 후보 분리·미전송 수정 stream 반영, 계정 lease 전환/자료 보존, 부분검색/빈 결과/발견 진입, 이전 stream 지연/오류 방어).
- 최종 일괄 flutter test --no-pub --reporter expanded: 878 PASS, 실패0(1분29초). analyze --no-pub: No issues found(4.4초). debug searchVerification APK build: PASS(36.3초). 기존 검색/등록/동기화/삭제/계정/보존 회귀 포함. Git 제외 p17-01 로그·APK/소스해시 보존.

## 현재 모델 별도 검토
- gpt-6.1-sol/medium, 사용자 지정 유지. 원본 완료 기준·실제 변경·실행 결과 별도 대조 PASS. 새 계정 접근 경로는 기존 검증 lease를 재사용하고 네트워크 auth를 우회하지 않는다. scope 변경 때 이전 결과 제거, 개인 자료 write/녹음 snapshot/외부 번호 변환 추가 없음. 독립 에이전트/별도 모델 호출 없음.
- 학습: 목록의 화면 필터만으로 계정 격리를 보장할 수 없으므로 저장소에서 소유 계정/활성 상태를 한정하고 비동기 결과가 돌아오는 순간에도 현재 맥락을 대조한다.

## 설치본·다음
- tool/my_songs_verification.dart는 debug/searchVerification 별도 앱 ID 한정. 별도 임시 root의 합성 계정A/B·실제 SQLite/LocalRepository를 사용하며 개인 계정/기존 DB/서버에는 쓰지 않는다. 앱/DB 삭제·초기화 없음.
- USER-070: 초기 목록/검색·오프라인 수정·실제 계정 DB 전환·복귀 자료 보존을 설치본에서 확인한다. 필수 실기 전 푸시하지 않는다. 이후 명시 stage/커밋·원격 전체 범위 기준 저장·필수 Flutter CI 확인 후 P17-02 착수.

- 실제 R5CW618VA1M 기기 확인, 해시 일치 APK install-r Success·MainActivity Status ok. 현재 UI package com.android.systemui: 검증 화면 표시/실기 통과는 미확인. USER-0704개 행동 대기. 제품 명령/CI 감시 실행0, 미커밋 제품 변경과 기록 보존. 테스트878 PASS이며 중단한 실행의876중간값/SDK 파일잠금 재실행은 최종 통과로 합산하지 않는다.

- 종료 대조: --check-stop 종료0/WAIT/ready0/running0, USER-070 알림 SERVER_ACCEPTED(실제 수신 미확인), 현재 대화에4개 결과 질문 제시. 최초 측정 유지/로컬 로그 집계 refresh, 미커밋 변경 보존·제품 작업 실행0.

## 사용자 회신 대조 — 2026-10-10
- 첫 사진: 계정A 밤 산책만 표시, 휴지통 곡 제외가 정상. 이 화면은 휴지통 탐색 화면이 아니므로 휴지통 항목 자체가 없어야 한다.
- 두 번째 사진: 비행기 모드 표시와 SINGER 입력·Singer 곡 결과 확인. 로컬 가수 대소문자 무시 검색 정상. 사용자 나머지 성공 회신으로 오프라인 수정 및 계정 전환/복귀 검사를 통과로 보존한다.
- 없는곡 빈 결과는 사진/회신에 명시되지 않아 실제 기기 확인 시도. 첫 dump는 런처, 후속 adb 명령은 no devices로 실행되지 않았으며 통과 실적으로 세지 않는다. USER-070 판본2는 빈 결과1개만 확인한다. 코드 오류 근거 없으며 소스 수정/전체 실기 반복 없음.

- 최종 사용자 회신 “빈 결과도 정상”: 없는곡 입력 시 곡 행 제거·빈 상태 확인. USER-070 모든 필수 설치본 조건 통과, 직접 행동 제거. 검사 APK·주요 소스 해시 일치 재확인. 원격 HEAD 새 조회0e76d24, 필수 Flutter CI 대상.
