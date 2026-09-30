# P10-03b 서명 문제 — 외부 상담 요청 자료

2026-09-30 확인. 사용자에게 이미 받은 답은 “Android Studio에서 실행, 키 위치 모름”이다. 추가 키 정보 요청을 반복하지 않는다. 이 문서는 상담에 전달할 수 있는 자료이며, 지금 사용자에게 전달 행동을 새로 요청한 것은 아니다.

## 목표와 현재 문제

기존 앱과 데이터를 보존하면서 P10-03b의 새 동기화 화면/실제 Android 이탈→복귀 동작을 확인하려 한다. 기존 앱의 package는 `com.ksh321.songrecord.dev`다. 동일 package에 `adb install -r`로 새 APK를 업데이트하려면 Android가 허용하는 서명 관계가 필요하다. 현재 두 debug 인증서는 다르며 호환되는 서명 계보도 확인되지 않았다. 앱 삭제·데이터 초기화는 승인되지 않았고 실행하지 않았다.

기존 기능과 기존 Google/Kakao 로그인은 사용자 검증 완료다. 이번 문제는 새 변경 설치의 차단 사유이며 기존 기능을 미검증으로 되돌리는 근거가 아니다.

## 확인한 사실

- 새 APK: 코드 `2e6bd8826331caba39b3621e9ee63355fce10583`, dev debug, 1.0.0+1. 빌드 성공, 설치 실패. 이후 HEAD는 `5fd3e126c71dcedfd9598d9defbe0a98e772b614`이지만 고정 APK를 그 HEAD의 빌드로 취급하지 않는다.
- 기존 앱: 1.0.0+1, 정확한 코드 commit 미확인. APK만 읽기 전용으로 가져와 공개 인증서를 검사했다. 앱 데이터는 추출/삭제하지 않았다.
- `apksigner verify --print-certs`에서 확인한 **인증서 SHA-256**(APK 파일 해시 아님):
  - 설치된 앱: `e0fbdb61e5dcb91c77ec06d4a0f0e5b853a427297aac063975735803513bcb67`
  - 새 APK: `f09eb3788c2ac0104aba3e01442324badb1cbbd77d7d09bc5865001f05251573`
- 현재 `%USERPROFILE%/.android/debug.keystore` 공개 인증서는 새 APK와 일치한다. 기존 앱 인증서는 저장소의 과거 P06 인증 설정 기록과 일치한다.
- 실제 오류: `INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.ksh321.songrecord.dev signatures do not match newer version; ignoring!`
- private key는 APK의 공개 인증서에서 복원할 수 있는 것으로 가정하지 않는다.

## 확인한 경로와 설정 / 이미 시도한 방법

| 확인 대상 | 결과 |
|---|---|
| `%USERPROFILE%/.android/debug.keystore` 및 같은 폴더 | 현재 키 존재, 새 APK 지문과 일치. 기존 지문 키 미발견 |
| 현재 저장소, 외부 source, 관리 worktree의 `.keystore`/`.jks` | 기존 키 미발견 |
| `%APPDATA%/Google/AndroidStudio2026.1.2/options/recentProjects.xml` | 현재 프로젝트 및 `%USERPROFILE%/StudioProjects/song_record` 참조 확인 |
| 위 과거 StudioProjects 프로젝트의 키 파일·Gradle 설정 | 키 미발견, release도 기본 debug 설정 참조 |
| Android Studio 설정/로그의 키 경로·`user.home`·Android home override 흔적 | 다른 키 경로 미발견 |
| 현재 Java `user.home`, `ANDROID_USER_HOME`, `ANDROID_SDK_HOME` | 현재 사용자 home, 두 Android 변수 미설정. 과거 IDE 실행 환경을 증명하지는 않음 |
| 과거 프로젝트의 예상 app-debug/app-dev-debug APK 경로 | APK 없음 |
| 새 APK `adb install -r` | 위 서명 불일치로 거절. 재시도·삭제 설치 하지 않음 |

현재 `apps/mobile/android/app/build.gradle.kts`의 관련 설정은 다음과 같다. debug에 별도 `storeFile` 지정은 없다.

```kotlin
// buildTypes.release 내부
signingConfig = signingConfigs.getByName("debug")
// productFlavors.dev 내부
applicationIdSuffix = ".dev"
```

별도 환경 문제였던 Java selector/socket 오류는 실행별 짧은 socket 경로 지정으로 APK 빌드에 성공했다. 원래 개발 DB/볼륨은 보존했고 새 격리 DB/API는 준비했다. 이 성공은 서명 문제 해결이나 새 폰 실기 통과가 아니다.

## 아직 모르는 점

기존 APK를 실제로 서명했던 키의 위치/백업, 당시 IDE가 사용한 home/빌드 설정, 해당 키를 보유한 다른 PC 여부, 기존 APK의 정확한 commit. 현재 기본 키가 달라진 원인은 확인하지 못했다.

## 검토 중인 해결책과 구체적인 질문

1. 이전 대화/작업 기록에 기존 지문의 키를 생성하거나 옮긴 경로, 다른 PC/사용자 home, 서명 설정 변경 근거가 있는가? 있다면 **경로와 근거만** 알려 달라. 키 파일·암호·토큰은 보내지 말아 달라.
2. 일치하는 키를 발견하면 공개 인증서만 먼저 대조하고 동일 package 데이터 보존 업데이트를 검토한다. 현재 증거에서 빠진 안전한 키 위치 확인 경로가 있는가?
3. 키를 찾지 못하면 별도 package `com.ksh321.songrecord.verification`의 합성 테스트 앱을 병행하는 방안을 검토한다. 기존 앱을 건드리지 않고 아래 범위만 검증할 수 있는지, 누락된 위험은 무엇인가?
4. 삭제/재설치는 기본 해결책이 아니다. 현재 앱 데이터 보존을 보장할 근거 없는 백업/복원이나 서명 우회 방법을 제안하지 말아 달라.

## 별도 테스트 앱의 범위와 한계

아직 제안/준비 단계이며 APK·설치·실행 통과 근거는 없다. 실제 LoginGate/SyncController/SyncScreen과 메모리 합성 계정/backend로 새 UI, Android의 실제 pause→resume, 제한된 관찰 시간의 중복 실행을 자동 확인하는 방안이다. SDK의 실행 중 host handshake와 실제 앱 구성의 격리 근거를 추가 확인해야 한다. UI lifecycle을 코드로 주입한 테스트를 실기라고 기록하지 않는다.

이 방법으로 **기존 설치 앱의 데이터 보존 업데이트, 실제 Google/Kakao 인증과 callback 등록, 실제 서버/기존 계정 데이터 동기화, 기존 휴대폰 DB 이관, 녹음·사람의 청취**를 확인할 수는 없다. 새 package의 합성 테스트가 통과해도 P10-03 전체 완료로 판정하지 않는다. 지연 401/403 + 복귀 시 전송 1회·시도 [1,0]은 기존 자동 회귀 근거를 유지하며 사용자가 수동 재현하도록 요청하지 않는다.

외부 답변은 참고 자료다. 현재 코드·환경·기존 승인과 대조하고 새로운 파괴적 작업은 별도 승인 없이 적용하지 않는다.

## 2026-09-30 독립 준비 확인

설치된 Flutter SDK `integration_test/lib/src/_callback_io.dart`를 직접 읽었다. IO의 `request_data`는 allTestsPassed 완료를 기다리고, screenshot은 native channel의 captureScreenshot 결과를 반환한다. 따라서 Android에서 screenshot callback을 이용해 테스트 실행 도중 host HOME/복귀를 지시하는 초기 제안은 채택하지 않는다. extended driver의 최종 screenshots 처리와 실제 실행 중 제어를 혼동하면 교착/종료 후 조작이 될 수 있다. 별도 실행 중 handshake 설계가 필요하다.

실제 `SongRecordApp`은 주입 가능한 authController/syncController/recorderGateway를 받으며 settings route에 syncController를 전달한다. AppShell은 녹음 패널을 포함하므로 합성 recorderGateway 등 부수 효과 격리도 검토해야 한다. 새 flavor나 하네스 코드·설치 변경은 아직 적용하지 않았다. 외부 상담 전에도 수행 가능한 SDK/실제 코드 확인을 진행한 근거다.

## 2026-09-30 기존 ChatGPT 대화 상담 연결

사용자가 ‘워크플로우 순서 검토’를 지정했다. 이 기존 ChatGPT 대화에 send_message_to_thread로 서명 문제·공개 인증서 지문·조사 범위·구체적 질문만 전달했다. 새 세션 생성이나 CLI 코드 검수 실행은 하지 않았다. read_thread에서 전달한 질문 본문과 active 상태를 확인했다. 당시 답변은 아직 작성 중이므로 왕복 완료·서명 문제 해결로 기록하지 않는다. USER-007 선택 행동은 완료하여 직접 할 일 목록에서 제거했다.

## 상담 답변 수신 및 현재 근거 대조

2026-09-30 기존 ‘워크플로우 순서 검토’에 질문 전송 후 read_thread로 새 답변 수신 및 idle 확인. 메시지 ID fd2500ba-72ef-58f1-948b-cc672e5b502d. 기존 대화 질문→답변 읽기 왕복 연결을 실제 확인했다. 새 대화/별도 CLI 검수 세션은 생성하지 않았다.

상담 답변이 보고한 과거 검색 근거:
- 2026-09-23 22:00 KST: 과거 AI가 `C:/Users/ksh/Documents/GitHub/Song_Record/apps/mobile/android`에서 signingReport 실행을 안내.
- 2026-09-23 22:08 KST: 노트북 서명 확인 맥락에서 사용자가 설치 앱과 동일한 E0:FB:...:CB:67 SHA-256을 제출했다고 보고.
- 당시 Store 줄, 실제 키 위치/백업, 정확한 원문 대화 제목은 상담에서도 미확인. 이 로컬 작업은 해당 과거 원문 메시지를 별도로 직접 읽지 않았으므로 상담 보고와 직접 관측을 구분한다.

대조: 상담 답변의 전체 E0FBDB61E5DCB91C77EC06D4A0F0E5B853A427297AAC063975735803513BCB67은 기존 APK에서 확인한 인증서 지문과 일치한다. 현재 PC의 F09E...1573과는 다르다. 따라서 당시 노트북을 우선 확인할 근거는 생겼지만 키가 현재 존재하거나 업데이트 가능한 것으로 판정하지 않는다. 후보 `%USERPROFILE%/.android/debug.keystore`는 기본 위치일 뿐 확인된 과거 Store 경로가 아니다. 사용자에게 현재 PC 재탐색/동일 실기 대신 당시 노트북 파일 존재만 USER-008로 요청한다.

별도 verification 앱은 실제 UI/controller 재사용·합성 backend·독립 저장소와 provider/deep link 격리가 필요하다는 의견을 유지한다. 실제 OAuth/기존 앱 DB 이관/데이터 보존 업데이트는 대체하지 못한다. 기존 사용자가 확인한 기능은 완료 유지. 키를 발견해도 덮어쓰기/삭제/서명 변경을 바로 실행하지 않고 공개 인증서 일치부터 확인한다.

## 사용자 승인에 따른 새 설치 — 2026-09-30

사용자 원문: “기존 앱에 지워도 상관 없는 데이터만 있어서 상관 없음 걍 새로 깔아”. 이번 연결 USB 휴대폰의 `com.ksh321.songrecord.dev` 삭제와 새 설치에 한정해 적용했다. USER-008 노트북 키 확인 요청은 취소했다. 다른 앱/서버 DB/Docker 볼륨은 삭제하지 않았다.

- 삭제 전 USB device, 기존 package, APK package/version/activity 확인.
- 설치 APK: `.local/workflow/phone-build/2e6bd88-dev-debug.apk`, 코드 `2e6bd8826331caba39b3621e9ee63355fce10583`, SHA256 `4476036822714E2ED55F0A59AFA406F70EB79170081A6FC8740B4C095E66C8D8` 기존 빌드 기록과 일치.
- `adb -d uninstall com.ksh321.songrecord.dev`: Success.
- `adb -d install <위 고정 APK>`: Success. 설치 기록 2026-09-30 10:03:28, versionName 1.0.0/versionCode 1.
- `adb -d reverse tcp:8080 tcp:8080`, 로컬 API /actuator/health UP.
- `adb -d shell am start -W -n com.ksh321.songrecord.dev/com.ksh321.songrecord.MainActivity`: Status ok, COLD 실행 완료.
- pidof로 실행 프로세스 확인, 해당 PID logcat 수집 범위에서 FATAL EXCEPTION 없음. 무한 시간 오류 부재나 전체 기능 통과를 의미하지 않음.
- 실제 화면 수집/확인: Google/카카오 로그인 버튼이 있는 로그인 화면 표시. 원본 화면·로그는 Git 제외 로컬 폴더 보관.

판정: 서명 불일치의 데이터 보존 업데이트 경로 대신 사용자 승인 새 설치로 설치 차단 해소. 기존 앱 데이터는 삭제됐으며 데이터 보존 업데이트 성공이 아니다. 새 버전 로그인/동기화/이탈복귀 실기는 아직 미완료. USER-009 로그인만 사용자에게 요청하고 나머지 자동 수집 가능한 검증은 AI가 수행한다.

## 새 설치 후 로그인 실패 조사 — 2026-09-30

USER-009 사용자가 Google/Kakao 모두 실패 결과를 전달했다. 사용자 수행 완료이므로 내가할일.md에서 제거하고 AI 조사로 전환했다. 성공/실기 완료 아님.

직접 확인:
- 앱 로그인 시작 10:05:09 CredentialManager의 callingPackage=com.ksh321.songrecord.dev.
- 10:05:12 Google Auth.Api.Credentials에 `Unknown error [status=UNREGISTERED_ON_API_CONSOLE]`, 이후 Account reauth failed/GoogleSignIn flow failed. Google 공급자 인증 단계의 등록 설정 오류 근거다. 어떤 콘솔 항목이 누락됐는지(새 인증서 SHA-1/패키지/클라이언트)는 실제 콘솔 대조 전 미확인.
- 광범위 로그의 DEVELOPER_ERROR/네트워크 오류는 타 프로세스도 포함돼 이번 앱 원인으로 곧바로 적용하지 않았다.
- 현재 API health UP, USB tcp:8080→tcp:8080 존재. 이것만으로 휴대폰의 모든 HTTP 요청 성공을 증명하지 않는다.
- 현재 앱은 Google/Kakao 공급자 상세 예외를 일반 오류 문구로 바꾼다(auth_adapters.dart). 카카오 실패의 구체 오류 코드는 수집 근거 부족으로 미확인. Google 원인과 같다고 단정하지 않는다.

기존 ‘워크플로우 순서 검토’ 후속 상담(메시지 82c914e0-c3ff-5455-b080-c3eec6b860ab): 과거 Kakao OIDC 활성화 사용자 확인과 서버 연결 문제 전력/이후 로그인 성공 기록은 있었으나 정확한 해결 원인은 미확정. 과거 노트북 인증서 등록 안내는 있었고 새 PC 인증서 등록 여부는 모른다고 답했다. 현재 서버 설정의 환경변수 이름은 APK 설정과 같은 GOOGLE_SERVER_CLIENT_ID/KAKAO_NATIVE_APP_KEY를 참조하지만 콘솔 등록 일치를 뜻하지 않는다.

다음: 현재 PC 인증서의 Google Android 패키지/SHA-1 및 Kakao 키 해시 등록을 실제 공급자 콘솔과 대조. 기존 등록 삭제/대체나 OIDC 무조건 토글은 하지 않는다. 로그인 가능 여부를 확인하지 않은 설치 성공 안내를 인증 준비 완료로 확대하지 않는다. 코드 변경이나 추가 재설치는 아직 하지 않았다.

안전: 인증 properties 전체 출력 시도는 자동 승인 심사에서 비밀값 노출 우려로 거절됐고 실행되지 않았다. 이후 값 출력 없이 환경변수 참조 이름만 확인하는 안전한 방식으로 처리했다. 원문 로그는 Git 제외 로컬 파일에만 보관한다.

## 실제 공급자 콘솔 대조 — 2026-09-30

사용자가 개발자 콘솔에 로그인 후 AI가 읽기로 직접 확인했다.

| 대상 | 실제 등록 | 현재 설치 APK | 조치 |
|---|---|---|---|
| Google 프로젝트 song-record-dev | 웹 클라이언트와 Android 클라이언트 각 1개. Android package com.ksh321.songrecord.dev, SHA-1 EE:9D:7E:5E:E7:3D:6E:44:88:6E:33:54:0B:83:08:82:45:1D:82:C5 | 동일 package, SHA-1 7E:E8:02:8E:89:B2:63:BD:AD:18:EA:86:CC:29:BB:E7:36:98:F0:95 | 기존 2개를 보존하고 Current PC Android 항목 추가 필요 |
| Kakao 앱1586938 native 항목5727192 | 현재 APK의 native key와 동일, package com.ksh321.songrecord.dev, 해시 7p1+Xuc9bkSIbjNUC4MIgkUdgsU=만 등록 | 공개 인증서 SHA-1의 Base64 fugCjomyY72tGOqGzCm75zaY8JU= | 기존 값을 보존하고 새 해시 추가 필요 |

Google은 기존 실제 UNREGISTERED_ON_API_CONSOLE와 신규 package/SHA-1 조합 누락을 함께 확인했다. Kakao는 Google로부터 추정한 것이 아니라 사용 중인 정확한 플랫폼 키의 등록 누락을 독립 확인했다. 다만 Kakao 실패 당시 KOE/SDK 상세 오류는 보관 로그에 없고 예외가 일반 문구로 처리되어, 누락 외 다른 원인까지 해소됐다고 판정하지 않는다. 설정 보완 뒤 제한된 재시도에서 실제 결과/실패 코드 확인이 필요하다.

추가 사전 점검: 고정 APK kernel에 로컬 Google 웹 client/native key/API localhost8080 값 포함 여부를 값 출력 없이 확인(모두 true). Android Kakao scheme와 native key 일치 true. 서버 auth properties의 환경변수 참조 이름이 실행 스크립트와 일치. 설정 이름이 일치하는 것과 실제 로그인 성공은 구분한다.

공식 기준: [Google Android OAuth는 package와 SHA-1로 식별](https://codelabs.developers.google.com/sign-in-with-google-android), [Kakao 오류별 확인 기준](https://developers.kakao.com/docs/ko/kakaologin/trouble-shooting). 참고문서를 실제 로그인 오류의 대체 증거로 사용하지 않는다.

실행 상태: Google 새 Android 양식과 Kakao 추가 해시 입력 칸까지 열었으나 실제 값 입력 호출이 자동 승인 심사에서 거절됐다. 보안 인증 허용 대상 확대의 실행 직전 확인 요구. 저장은 수행하지 않았다. USER-011 승인 시 준비값 입력→기존 값 유지 확인→저장→재조회 후에만 앱 재로그인 요청. 사용자 권한 요구를 우회하지 않는다. 이 거절은 코드 수정 실패 횟수로 세지 않는다.

## 승인된 설정 보완 완료 및 다음 차단

사용자가 USER-011 “두 곳 추가 등록 승인”이라고 명시했다. 승인 후 실제 콘솔에서 입력/저장했다.

- Google `Song Record Dev Android - Current PC` 생성 성공 안내 확인. 목록에 새 Android + 기존 Android + 기존 Server 웹 클라이언트 총3개 존재. 새 상세를 다시 열어 package와 SHA-1이 현재 APK 값과 일치 확인. 기존2개 삭제/교체 없음.
- Kakao native 항목5727192 저장 후 목록으로 나갔다가 다시 열어 기존 `7p1+Xuc9bkSIbjNUC4MIgkUdgsU=`와 새 `fugCjomyY72tGOqGzCm75zaY8JU=`가 함께 저장된 것 확인. 기존 package/native key 보존. 비동기 화면의 초기 캐시에는 예전1개가 잠깐 보였으나 최종 조회는2개로 확인.
- Kakao 로그인 일반 페이지에서 로그인 ON, OpenID Connect ON을 읽기로 확인. 토글하지 않음.
- 실제 새 로그인 성공과 카카오 실패 전체 원인 해소는 미검증. 기존 실패 상세 오류 코드 부재를 성공 추정으로 채우지 않음. 보완한 구성의 재시도와 필요 시 새 오류 수집으로 최종 판정.
- Google 콘솔 안내: 설정 반영에 5분~몇 시간 소요 가능. 저장 성공과 공급자 전파 완료는 별개.
- 최종 사전 확인에서 API health UP이나 ADB get-state/reverse 조회는 no devices found. USER-012 USB 재연결 요청. 기기 연결 후 reverse와 시간 범위를 지정한 로그 수집을 준비하고 그 다음 로그인 재시도 요청.
- 앱 재빌드/설치·코드 변경·기존 서버 데이터 삭제는 이번 보완에 필요 없어 수행하지 않음. 인증 콘솔 변경은 Git commit 자체로 검증할 수 없으므로 위 실제 콘솔 관측을 근거로 기록.

이 작업의 남은 차단은 현재 USB 연결과 보완 후 실제 인증 결과다. 사용자: USB 연결 회신. AI: device/reverse/API·로그 준비 확인 후 두 공급자 변경 범위만 검증. 로그인 실패 시 계정 정보 없는 SDK 오류 코드/서버 상태를 구분하여 조사한다.


## 2026-09-30 USER-013 결과와 Google 시간 검증 조사

- 사용자 직접 결과: Kakao 성공, Google 인증 정보 확인 불가. 앱은 고정 2e6bd88 dev 1.0.0+1이며 코드/인증 검사 변경 없음.
- 로컬 API 로그에서 AUTH_INVALID_PROOF 3건 확인. 이전 Google SDK UNREGISTERED_ON_API_CONSOLE과 달리 서버 검증 단계 오류다. 원본 로그는 .local/workflow/p10-phone-api.log, 개인 식별 요청 값은 여기 복사하지 않음.
- GoogleProofVerifier.java는 Clock.systemUTC 기반 iat > now+60초를 거절한다. 기존 future-issued-at 테스트/검사를 유지한다. 사용자 토큰을 직접 열람한 것은 아니므로 유력 원인과 실제 재시도 성공을 구분한다.
- 실행: Google 인증서 endpoint GET의 HTTP Date/Age와 PC DateTimeOffset.UtcNow 비교, adb shell date -u, w32tm /query /status. PC UTC 01:50:45, Google Date 01:56:32 + Age19초, 기기 01:56:50. 요청 367ms. Google 헤더만 비교해도 PC보다 347초 앞서며 기기는 약365초 앞선다.
- Windows 시간 상태는 leap3/stratum0/Local CMOS Clock/최근 동기화 없음. w32tm /resync 실행 결과 0x80070005 접근 거부. 환경 권한 오류이며 제품 수정 실패 카운트에 포함하지 않음.
- USER-014 Windows 설정에서 직접 동기화 요청. 회신 후 시각 오차/API 준비 재확인→Google만 한 번 로그인 검증. Kakao 반복 재시험 요청 없음. P10-03b 실제 동기화/복귀 검증은 아직 완료 아님.
- Git HEAD 5fd3e126c71dcedfd9598d9defbe0a98e772b614 유지. EXPORT 및 WORKFLOW-08 미커밋 변경 보존; 별도 검수 차단도 유지. 이 환경 조사로 제품 코드 변경/테스트 반복/커밋·푸시하지 않음.

### 시간 동기화 UI 실패 후 추가 진단

USER-014 두 번 실패 화면을 수신했다. W32Time Running/Automatic. 제한된 실행의 stripchart timeout과 네트워크 권한 있는 실행을 구분했다. 후자에서 time.windows.com 응답 +365.7741150초, time.google.com timeout. Google HTTPS Date+Age 역시 약366초 차이. time.windows.com 전체 접속 불가/인터넷 단절로 결론 내리지 않는다. stripchart와 W32Time 클라이언트의 UDP 출발 포트가 달라 probe 성공만으로 서비스 연결을 보장하지 않는다. [Microsoft 공식 설명](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings).

AI 실행의 configuration 조회 및 기존 resync는 0x80070005. 관리자 Windows 토큰을 확보했다고 주장하지 않는다. USER-015 관리자 PowerShell resync /rediscover 및 status 출력 요청. 방화벽 해제·서비스 재등록·인증 검증 완화 없음. 기존 UI 버튼 반복 요청 없음. 결과 후 시각 대조 및 Google만 새 검증. 독립 EXPORT/WORKFLOW-08 별도 검수 차단은 유지하며 권한을 우회하지 않는다.

### 관리자 재검색 실패 후 현재 판정

USER-015 결과: 시간 데이터 없음, leap3/stratum0/Local CMOS Clock/최근 동기화 없음. 같은 명령 반복하지 않음. 레지스트리 읽기 결과 Type=NTP, server=time.windows.com,0x9, NtpClient Enabled=1, SpecialPollInterval=16384. Get-WinEvent System/Microsoft-Windows-Time-Service 최근 기록에서 이벤트47(8회 연결에도 유효 응답 없음),36(장기간 동기화 불가)을 확인. 158은 비HyperV 환경의 공급자 중지 설명이며 이 원인으로 단정하지 않음. 방화벽/네트워크 차단 위치는 미확정, 방화벽 해제나 규칙 추가 없음.

USER-016 휴대폰 기준 수동 시간 보정 요청. 자동 시간 설정을 잠시 끄는 임시 조치이며 자동 동기화 문제 해결은 아님. 회신 후 PC/외부/기기 초 단위 오차와 API 상태 확인, 그 뒤 Google만 새 검증. Kakao 사용자 성공 유지. 제품 변경/재시험/실기 완료 추정 없음. 독립 EXPORT 및 WORKFLOW-08은 기존 별도 검수 권한 차단을 유지한다.

### USER-016 수동 보정 확인 및 USER-017 준비

PC UTC02:24:07.139 / Google Date02:23:01+Age38(PC 약28.1초 앞섬) / USB 기기02:23:40(약27초 차이). 약6분 지연은 해소되어 iat 미래60초 검사 기준 안이다. 자동 동기화 복구는 미완료이고 토큰 실제 재검증 성공은 아직 추정하지 않음. ADB device, API health UP. 비어 있던 reverse8080을 재설정하고 확인. 설치버전1.0.0+1·설치시각10:03:28 동일. 기존 logcat 프로세스 없어 새 google-clock-retry.log 수집 시작. USER-017 Google만 1회 요청. Kakao 성공 유지. 제품 코드 수정/테스트 반복 없음.

### 로그인 준비 차단 해소 — 사용자 확인

USER-017 Google “성공” 답변 수신. USER-013 Kakao 성공과 함께 두 공급자 사용자 로그인 확인 완료. 현재 PC 인증서 추가 등록과 PC 시각 수동 보정 후 성공이며 제품 인증 검사 변경 없음. 자동 시간 동기화는 미복구이고 추후 시각 재이탈 가능성은 환경 항목으로 추적. 기존 기능 검증을 되돌리지 않으며 P10-03b 실기는 별도 USER-018로 진행. API UP/USB device 재확인, 로컬 로그 존재 확인. 비밀값·개인 데이터는 문서에 복사하지 않음.
