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
| 개발 API 기본값 | Android Emulator용 `http://10.0.2.2:8080` |

staging/prod의 `.invalid` 주소는 안전한 자리표시자다. 실제 배포 주소는 `API_BASE_URL`로 주입한다. 서버 DB·R2 비밀값은 앱에 넣지 않는다.

## 실행

저장소 루트에서:

```powershell
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run --flavor dev --dart-define=APP_ENV=dev
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
