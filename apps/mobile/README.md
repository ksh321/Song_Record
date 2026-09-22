# Flutter Android 앱

P01-02 실행 가능한 Flutter 골격이다.

## 확정 설정

| 구분 | 값 |
|---|---|
| Flutter / Dart | 3.47.4 stable / 3.13.3 |
| 운영 앱 ID | `com.ksh321.songrecord` |
| 개발 앱 ID | `com.ksh321.songrecord.dev` |
| 검증 앱 ID | `com.ksh321.songrecord.staging` |
| 환경 | `dev`, `staging`, `prod` |
| 초기 라우트 | `/` |
| 개발 API 기본값 | Emulator용 `http://10.0.2.2:8080`; 실제 기기는 실행 시 주소 주입 |

staging/prod의 `.invalid` 주소는 안전한 자리표시자다. 실제 배포 주소는 `API_BASE_URL`로 주입한다. 서버 DB·R2 비밀값은 앱에 넣지 않는다.

## 실행

저장소 루트에서:

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id> --flavor dev --dart-define=APP_ENV=dev
```

검증 환경:

```powershell
flutter run --flavor staging --dart-define=APP_ENV=staging --dart-define=API_BASE_URL=https://검증서버주소
```

운영 빌드:

```powershell
flutter build appbundle --flavor prod --dart-define=APP_ENV=prod --dart-define=API_BASE_URL=https://운영서버주소
```

Android flavor와 `APP_ENV`는 같은 환경을 사용한다. `API_BASE_URL`에는 비밀값이나 토큰을 넣지 않는다.

- 기술 기준: [D01](../../docs/decisions/D01-implementation-stack.md), [버전 목록](../../docs/contracts/toolchain-versions.md)
- 화면 기준: [원본 자료](../../docs/reference/)
- 공통 데이터: [fixtures](../../fixtures/README.md)


## USB 실제 기기 검증

P01-02는 Samsung SM A546S, Android 16(API 36)에서 dev debug 앱 실행을 확인했다.

서버가 생긴 뒤 USB 연결로 PC의 8080 포트를 사용할 때:

```powershell
adb reverse tcp:8080 tcp:8080
flutter run -d <device-id> --flavor dev --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

`adb reverse`는 USB를 다시 연결하거나 기기를 재부팅한 뒤 다시 실행할 수 있다.


## P01-06 Spring Boot health 연결

개발 앱은 `GET /actuator/health`를 호출하고 응답 상태와 원문 JSON을 화면에 표시한다. 앱에는 MySQL 주소·계정·비밀번호를 넣지 않는다. Flutter는 Spring Boot API만 호출하고 Spring Boot가 MySQL에 연결한다.

### API 주소 규칙

| 실행 대상 | API 주소 | 설명 |
|---|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8080` | 에뮬레이터에서 개발 PC를 가리키는 전용 주소 |
| 실제 기기 USB | `http://127.0.0.1:8080` | 먼저 `adb reverse tcp:8080 tcp:8080` 실행 |
| 실제 기기 같은 Wi-Fi | `http://<PC IPv4>:8080` | PC·휴대폰이 같은 사설망이고 Windows 방화벽의 개인 네트워크 허용 필요 |
| staging·prod | HTTPS 주소 | 현재 자리표시자이며 운영 주소 확정 전 사용 금지 |

로컬 HTTP 허용은 Android `debug` manifest에만 설정했다. release 빌드에는 적용되지 않는다.

### 실제 기기 USB 실행

Spring Boot를 dev 프로필로 먼저 실행한다. 다른 PowerShell에서 다음을 실행한다.

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse --list

cd C:\Users\shoon111111\Documents\GitHub\Song_Record\apps\mobile
flutter run -d R5CW618VA1M --flavor dev --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

앱 화면에 `서버 연결 성공: UP`과 `응답: {"status":"UP"}`이 나오면 실제 기기 연결 성공이다. 실패하면 Spring Boot 실행 상태, USB 디버깅 승인, `adb reverse --list`의 `tcp:8080 tcp:8080`을 확인하고 앱의 `다시 확인`을 누른다.

USB를 뽑거나 매핑을 지우려면 다음 명령을 사용한다.

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse --remove tcp:8080
```

### 에뮬레이터 실행

dev 기본 주소가 이미 `10.0.2.2:8080`이므로 별도 주소 없이 실행한다.

```powershell
flutter run --flavor dev --dart-define=APP_ENV=dev
```


### P01-06 실제 기기 검증 결과

2026-09-17 Samsung SM A546S에서 dev debug 앱을 실행하고 USB `adb reverse`로 PC의 Spring Boot에 연결했다. 앱 화면에서 health 상태 `UP`을 확인했다. 기존 개발 APK와 새 APK의 서명이 달라 최초 설치가 거부됐으나 기존 dev 패키지를 제거한 뒤 재설치해 해결했다.


## P01-07 공통 API 오류 표시

서버가 공통 오류 JSON을 반환하면 Flutter가 `code`, 사용자 메시지, `retryable`, `request_id`, `details`를 파싱한다. 현재 health 화면은 실패 메시지 아래에 오류 코드와 요청 ID를 표시하므로 서버 로그와 같은 요청을 찾을 수 있다.

앱은 오류 응답의 `message`만 사용자용 문장으로 사용하고, 토큰·비밀번호·메모·서명 URL을 화면이나 로그에 출력하지 않는다. 공통 계약이 아닌 응답은 기존 HTTP 상태 오류로 처리한다.


### P01-07 검증 결과

2026-09-17 Windows 11에서 `flutter analyze`와 `flutter test`가 모두 성공했다. 공통 오류 JSON 파서가 오류 코드·메시지·재시도 여부·요청 ID·상세 정보를 읽고, 계약에 맞지 않는 JSON을 거부하는 테스트를 확인했다. 서버의 실제 오류 요청에서도 동일 요청 ID가 응답과 서버 로그에 연결됐다.


## P01-08 CI

GitHub Actions의 `Flutter analyze and test` 작업은 Flutter 3.47.4 stable을 설치하고 다음 검사를 수행한다.

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

`--enforce-lockfile`은 저장소의 `pubspec.lock`과 다른 의존성 해석이 필요한 경우 실패시켜, 개발 PC와 CI가 같은 패키지 조합을 사용하도록 한다.

## P02-01~03 Android 녹음 시제품

개발 화면 아래쪽의 `녹음 시제품`은 Flutter `RecorderGateway`를 통해 Android 네이티브 `RecorderService`를 제어한다. 녹음은 화면에서 사용자가 버튼을 누른 경우에만 시작하며, 앱 내부 `files/recordings`에 AAC 96kbps·48kHz·모노 M4A를 저장한다.

```powershell
flutter run --flavor dev -t lib/main.dart
```

마이크·알림 권한을 허용하고 5~10초 녹음한 뒤 종료한다. 화면에 실제 MIME, 48000Hz, 채널 1이 표시되는지 확인하고 `녹음 파일 재생 확인`을 누른다. 6분 자동 종료와 사전 경고는 P02-04 이후 범위다. 전체 실기 절차는 [검증 문서](../../docs/verification/P02-01-03-recorder.md)를 따른다.

## P04-08 계정별 로컬 저장 기반

`lib/core/database`는 D01의 Drift/SQLite 구현이다. 앱 세션에서 `AccountStoreManager` 하나를 소유하고 인증 완료된 UUID로 `openAccount`를 호출한다. UI/저장소는 반환된 `AccountStore`를 사용하며 저수준 DB/파일 경로를 직접 열지 않는다. 로그아웃/계정 전환 호출 즉시 이전 세션은 무효화되지만 DB와 음성 파일은 보존한다. UUID 전달만으로 인증이 되는 것은 아니다.

앱 전용 지원 폴더 아래 `song_record/<dev|staging|prod>/accounts/<user UUID>/`에 `account.sqlite`, `audio`, `pending`, `imports`를 둔다. `account.sqlite`의 소유자/환경을 재확인하고, 파일 경로는 정해진 계정 상대 경로만 허용한다. 서버 object key/URL은 로컬 파일 경로가 아니다. 이 구조는 앱 내부 접근 분리이며 암호화는 아니다.

```powershell
cd C:\Users\shoon111111\Documents\GitHub\Song_Record\apps\mobile
flutter pub get --enforce-lockfile
dart run build_runner build
dart run drift_dev make-migrations --no-test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --flavor dev -t lib/main.dart
```

생성된 `account_database.g.dart`는 직접 고치지 않는다. 공개한 v1 스키마 보존본은 후속 버전으로 덮어쓰지 않는다. 구조 변경에는 `schemaVersion` 증가, 명시적 보존 마이그레이션, 이전 데이터 테스트가 필요하다. 버전 불일치나 계정 불일치에 DB 삭제/초기화로 복구하지 않는다. CI가 생성 코드와 스키마 일치를 검사한다.

현재 P04-08은 로그인·UI·P02 네이티브 녹음과 미연결이다. 기존 `prototype_device` journal과 음성을 새 계정 폴더로 자동 이전하지 않는다. P06 인증 연결, P10 동기화/ACK/충돌 처리, P18 네이티브 journal/파일 복구, P22 실제 ZIP 가져오기에서 이 기반을 확장한다. 아직 일반 화면 기능 완성을 의미하지 않는다.

2026-09-21 로컬 검증: 별도 Windows 시험 폴더, SQLite 3.51.1에서 analyze 문제 없음·전체 테스트 57개 통과/링크 권한 검사 1개 보류. 원본 설정과 다른 시험용 SQLite 사용 범위 및 GitHub 대기 상태는 [P04-08 보고서](../../docs/verification/P04-08-account-local-storage.md)를 따른다.


## P05-01 공통 테마

`lib/core/theme/app_tokens.dart`는 `docs/reference/ui_reference_palette.json`의 색상·글자·치수를 정의한다. `AppTheme.dark()`의 초기 강조색은 블루다. 다른 강조색은 `SongRecordApp(accent: AppAccent.white, ...)`처럼 주입할 수 있으며 사용자 설정의 영속 저장은 아직 연결하지 않았다. 녹음 시작·종료 스타일은 선택한 강조색과 무관하다.

실제 앱의 기본 진입점은 계속 `lib/main.dart`다. 기존 flavor와 `API_BASE_URL` 실행 인자를 그대로 사용한다. 개발용 테마 미리보기는 서버나 마이크를 사용하지 않는다.

```powershell
flutter run --debug --flavor dev -t tool/preview_theme.dart
```

미리보기에서 8개 강조색을 눌러 주요 버튼의 글자와 배경, 흰색 선택의 검정 글자, 녹음 빨강과 키 배지의 고정 색을 확인한다. 이 도구는 실제 녹음이나 데이터 저장을 하지 않는다. 확인 후 원래 앱은 기존 실행 설정에서 `lib/main.dart`로 다시 실행한다.

코드 분석과 테스트, Android 실기·CI 확인 상태는 [P05-01 보고서](../../docs/verification/P05-01-theme-tokens.md)를 따른다.
