# P06-06 — 앱 로그인, 보안 저장, 세션 갱신

> 현재 상태 (2026-09-29): **기존 기능 사용자 검증 완료**. 기준 HEAD와 확인 원문은 [사용자 확인 기록](../progress.md#user-acceptance-20260929)을 따른다. 아래 검증 대기/미실행 표현과 체크리스트는 당시 이력이며, 문서 부족만으로 재실기를 요청하지 않는다. 개별 사례의 실행 횟수·명령·기기를 새로 확인한 것으로 기록하지 않는다. 이후 변경과 영향 범위는 별도로 검증한다.

작성 당시 상태: 구현 및 서버 자동 검증 완료. Windows Flutter 분석/전체 테스트/Android 실기 검증 대기.
기준 커밋: c42207259f6d2fca08de90f6fdd1c22826ab80a3 (P06-05).

## 바뀐 코드

- 서버 `SocialAuthController`: POST `/v1/auth/social`, POST `/v1/auth/refresh`, GET `/v1/auth/me`.
  Google ID token / Kakao access token을 기존 검증기로 확인한 뒤 계정을 등록/조회하고 기존 SessionService로 세션을 발급한다.
  클라이언트가 보낸 사용자 ID/이메일로 계정을 선택하지 않는다. 새 로그인마다 서버가 device UUID를 생성한다.
- `AuthHttpSecurityConfiguration`: 해당 모바일 인증 경로만 별도 stateless 체인으로 처리한다.
  `/me`는 컨트롤러에서 Bearer와 X-Device-Id를 함께 검증한다. 기존 기타 경로 denyAll은 유지한다.
  성공 응답에 no-store/no-cache, 세션 쿠키 없음. 잘못된 JSON은 토큰을 반사하지 않는 400 응답.
- 앱 `features/auth`: 로그인 화면, 취소/실패 안내, 재시도, 보안 세션 저장, 재실행 복원, 만료 직전 갱신.
  Android Keystore 기반 flutter_secure_storage에 앱 세션을 저장한다. 환경과 API 주소별 저장 키를 분리한다.
  카카오 제공자 토큰은 사용자 정의 메모리 TokenManager를 사용하고 교환 후 제거한다. SDK 로그는 끈다.
- 갱신 동시 호출은 한 Future를 공유한다. 갱신 전 secure storage에 pending 표시를 기록하고 새 토큰 저장 후 표시를 없앤다.
  응답 유실/앱 종료로 갱신 결과가 불확실하면 이전 토큰을 다시 보내지 않고 재로그인을 요구한다.
  이 정책상 갱신 순간의 통신 실패도 재로그인이 필요할 수 있다.
- 로그인 및 복원에서 서버가 확인한 user UUID로 AccountStoreManager를 연다.
  인증 만료는 저장소 핸들과 인증 정보만 정리한다. 기존 DB·음성 파일·pending mutation은 삭제하지 않는다.
- Android 카카오 콜백/패키지 조회 등록, 인증 정보 백업/기기 이전 제외.
  dev만 제공받은 Kakao scheme을 설정했다. staging/prod 제공자 등록은 별도 배포 준비 사항이다.

## 범위 구분

이 단계는 실제 소셜 로그인과 서버 세션의 연결이다. 기존 앱 본문은 아직 메모리 샘플 UI다.
저장소를 계정별로 여는 것과 곡/녹음 UI를 영구 데이터에 연결하는 것은 다르다.
pending 데이터 보존 및 같은 계정 저장소 재개를 제공하며, 실제 업로드 큐 실행은 P10에서 연결한다.
명시적 계정 연결은 P06-07, 서버 세션 폐기를 포함한 로그아웃/연결 해제는 P06-08 범위다.

## 자동 검증 결과

- 별도 Linux 작업 환경, JDK 21, gradle.lockfile의 라이브러리 버전으로 auth 소스와 테스트를 직접 javac/JUnit 실행.
- 기존 108개 + 이번 컨트롤러/HTTP 보안 13개 = **121개 통과**, 실패 0.
- 포함: 제공자 분기, 잘못된 proof 차단, 입력 검증, 실제 HTTP JSON 처리, CSRF 쿠키 없이 로그인,
  미인증 /me 차단, 나머지 경로 접근 차단, 응답 no-store, UTC 만료시간, DTO 토큰 비노출.
- 전체 Gradle 빌드/실제 MySQL 기동/실제 Google·Kakao 계정 인증을 이 결과에 포함하지 않는다.
- Dart 3.13.3 formatter로 변경된 6개 Dart 파일 문법/포맷 확인.
- Flutter SDK 다운로드 실패로 이 환경에서는 Flutter analyze/test/APK 빌드를 실행하지 못했다.
  앱 테스트 14개를 추가했으며 실행 결과는 사용자 Windows 검증으로 확인한다.
  pubspec.lock은 기존 것을 유지했고 `flutter pub get`으로 실제 의존성을 해석한 결과를 함께 커밋해야 한다.

## Windows 자동 검증

ZIP의 Apply-P06-06.ps1이 패치 검사/적용 → 서버 test/bootJar → flutter pub get → format → analyze → test를 수행한다.
어느 단계든 실패하면 멈춘다. 부분 적용/기존 코드 불일치 시 강제 덮어쓰지 않는다.
이미 적용한 코드의 검증만 다시 실행할 때는 `-VerifyOnly`를 사용한다.

## 실기 확인 6개

서버 창은 계속 켜 두고, USB 연결과 디버깅 승인을 유지한다. adb reverse로 서버를 휴대폰에 연결한다.
빠른 갱신 검증은 서버 스크립트에 `-FastExpiry`를 지정한 뒤 새로 로그인한다(새 access token 1분).

1. Google 버튼 → 계정 선택 → 본문 진입. 빨간 오류 화면이 없어야 한다.
2. 앱을 완전히 종료 후 재실행 → 온라인에서 로그인 선택 없이 본문 복원.
3. 앱을 홈으로 보낸 뒤 70초 기다리고 복귀 → 재로그인 없이 갱신된다(FastExpiry 서버 사용).
4. 로그인 선택을 취소 → 로그인 화면에서 취소 안내, 버튼을 다시 누를 수 있다.
5. 카카오 버튼 → 카카오톡 또는 계정 로그인 → 본문 진입. 취소도 확인한다.
6. 로그인 화면에서 서버를 잠시 종료하고 로그인 시도 → 실패 안내와 재시도 가능.
   서버 재시작 후 로그인하면 정상 진입. 토큰·비밀번호가 화면/로그에 나타나면 안 된다.

4~6에서 로그인 화면으로 돌아가려면 모바일 스크립트의 `-ResetLogin`을 사용한다.
이것은 dev debug 검증 전용: 로컬 앱 세션만 지우며 DB/음성을 삭제하지 않고, 서버 세션 폐기는 하지 않는다.
해당 옵션으로 빌드한 앱은 콜드 스타트마다 초기화하므로, 복원 검증 전에는 옵션 없이 다시 실행해야 한다.
정상 배포 빌드에서는 이 옵션이 작동하지 않는다.

실기 결과 6개와 Windows 자동 검증이 통과한 뒤에만 P06-06 완료로 처리한다.

## 참고

- https://pub.dev/packages/google_sign_in/versions/7.2.0
- https://developers.kakao.com/docs/latest/ko/flutter/getting-started
- https://developers.kakao.com/docs/latest/ko/flutter/kakaologin
- https://pub.dev/packages/flutter_secure_storage/versions/10.3.4
