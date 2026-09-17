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
