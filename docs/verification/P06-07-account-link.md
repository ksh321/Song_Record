# P06-07 명시적 로그인 계정 연결

기준 커밋: d38b64c7fe694954068ba39a692f0968b186aae3 (P06-06 CI 수정).
이전 CI run 36222825161: 서버, Flutter/Android, MySQL 검증 모두 성공.
이번 단계 상태: 구현 및 서버 인증 테스트 완료. Windows 전체 검증, 실기 검증, 새 CI는 대기.

## 변경 내용
- 설정 → 로그인 계정 연결: 연결된 Google/카카오 표시, 기존 로그인 재인증 → 새 로그인 인증 → 연결.
- 이메일이 같아도 자동 연결/병합하지 않는다. 다른 사용자의 identity는 IDENTITY_IN_USE로 거절한다.
- V9 auth_link_challenge: 세션에 묶인 5분/1회용 요청, nonce는 해시만 보관. 기존 세션/계정 데이터 유지.
- 고정된 제공자 JWKS로 서명, issuer, audience, 시간, 요청별 nonce 검증. 인증 토큰은 로그/DB에 기록하지 않는다.
- 기존 identity 소유권을 재인증에서 확인한다. 연결 직전 사용자/기기/세션 활성 상태를 다시 검사한다.
- 동시 연결과 재사용을 트랜잭션 및 identity 고유 제약으로 막는다.
- Google Android Credential Manager의 요청별 nonce 인증 브리지 추가. 카카오는 SDK 브라우저 로그인 및 nonce 사용.
- 카카오 SDK가 제공하는 PKCE 경로를 사용한다. 비밀번호 입력 여부는 제공자의 인증 화면 정책을 따른다.
- 해제, 사용자 계정 병합, 로그아웃 기능은 이 패치에 포함되지 않는다.

## API
모든 요청은 Authorization Bearer 및 X-Device-Id 필요.
- GET /v1/auth/identities
- POST /v1/auth/identities/reauth-challenges: provider, targetProvider
- POST /v1/auth/identities/link-challenges: challengeId, proof (기존 identity ID token)
- POST /v1/auth/identities/link: challengeId, proof (새 identity ID token)
응답 Cache-Control no-store. 오류는 기존 error.code 봉투 사용.

## 검증 근거
2026-09-26 별도 Linux 실행 환경, Java 21 + JUnit Console로 auth 패키지 154개 실행/성공/실패 0.
이 수치는 Gradle 전체 빌드 결과가 아니다. 직접 javac로 실제 main/test 코드를 컴파일하여 실행했다.
신규 서비스 테스트 17개, 신규 서명 검증 테스트 14개, 기존 HTTP 테스트에 신규 2개 포함.
만료/재사용, 재인증 생략, 기존 identity 불일치, 세션/기기 폐기, 삭제 중 사용자, 다른 계정 충돌,
이메일 동일 계정 분리, 동시 요청 단일 성공, 두 사용자의 동일 identity 동시 확보를 검증했다.
Dart 포맷 파싱, Python AST, bash -n 완료.
Flutter SDK/Android SDK/Docker가 이 환경에 없어 Flutter 테스트/분석, APK 빌드, MySQL 실검증은 실행하지 않았다.
Flutter 회귀 테스트 8개(흐름/UI 6, HTTP 오류 2)를 추가했다. 실행은 Apply-P06-07.ps1에 포함.
MySQL CI는 기존 V7/V8 검증을 유지하고 V8→V9 업그레이드/제약/세션 삭제 연쇄 검증을 추가했다.

## Windows 실행
기존 Song Record 서버가 켜져 있다면 그 창에서 Ctrl+C로 종료한다. Oracle 프로세스를 종료하지 않는다.
Docker Desktop 실행, JDK 21 및 기존 infra/.env를 그대로 사용한다.
1. Apply-P06-07.ps1: 패치 검사/적용(이미 적용됐으면 검증만), 서버 test bootJar, Flutter analyze/test, debug APK 빌드.
2. Start-P06-07-Server.ps1: MySQL 준비, 127.0.0.1:8081 서버 실행. 이 창을 유지한다.
3. 다른 창 Run-P06-07-Mobile.ps1: USB 터널 및 실제 앱 실행. 일반 실행은 -ResetLogin 없이.
실패하면 다음 명령으로 넘어가지 않고 실패 출력을 확인한다. 패치는 강제로 재적용하지 않는다.

## 실기 확인 (취소/충돌은 연결 성공 전에 검사)
1. 설정 → 로그인 계정 연결. 현재 로그인 수단은 연결됨, 다른 수단은 연결 버튼 표시.
2. 연결 → 설명 창에서 취소. 연결 목록과 현재 로그인 유지.
3. 본인 확인 시작 → 제공자 인증 화면에서 취소/뒤로. 앱 복귀 후 연결되지 않고 다시 시도 가능.
4. 기존 계정 인증을 마치고 새 제공자 화면에서 취소. 연결되지 않고 현재 계정 유지.
5. 이미 다른 노래기록 계정으로 가입한 제공자 계정을 선택. 다른 계정에서 사용 중 안내, 목록/기록 그대로.
6. 노래기록에 아직 가입하지 않은 제공자 계정으로 완료. 두 수단 연결됨. 화면 재진입/앱 재시작 후에도 유지.
7. 연결한 수단으로 재로그인하여 동일 노래기록 계정인지 확인. 현재 userId는 /v1/auth/me에 해당한다.
   앱 userId 표시가 없다면 같은 기존 내 곡/녹음 데이터가 있는 계정으로 확인한다.
   검증용 -ResetLogin 실행은 세션 자격 정보만 지우므로 서버 계정/로컬 DB를 삭제하지 않는다.
   재로그인 확인 후 반드시 옵션 없이 다시 실행한다.

이미 Google와 카카오로 각각 가입했다면 두 identity는 서로 다른 계정이다. 이 경우 5번 차단이 정상이다.
6번용 미가입 로그인 계정이 없다면 그 항목은 '미검증'으로 남겨 보고한다. DB 삭제/강제 병합으로 통과시키지 않는다.
검증용으로도 타인의 계정을 사용하지 않는다.
작은 화면/큰 시스템 글꼴에서 설명과 버튼에 접근 가능한지도 확인한다.

## 완료 조건
Windows 자동 검증, 가능한 실기 항목 결과, push 후 CI가 모두 확인돼야 이 단계를 완료로 기록한다.
미검증 항목은 그대로 표시한다.
추천 커밋 메시지: feat(auth): add explicit Google and Kakao account linking
