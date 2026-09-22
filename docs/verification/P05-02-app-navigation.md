# P05-02 앱 탐색 골격

2026-09-22. 기준 커밋 `f8c31f295ea79b43a8124698ad881a8282027784`.
상태: **P05-02 완료**. `46f471e24db0a6b0473f33c263d731740e623d9f`로 코드·문서 12개를 반영했다.
[CI 35736145931](https://github.com/ksh321/Song_Record/actions/runs/35736145931)의
Flutter 분석·테스트·Android APK, MySQL, Spring Boot 세 작업이 모두 성공했다.

## 기준과 범위

코드구현계획서 v1.0 P05-02와 구현설계서 v1.11의 1.1·2.1을 따른다.
탭은 내 곡, 인기 차트, 녹음, 플레이리스트, 검색 순서다. 설정은 공통 상단 진입이며
하단 탭을 대체하지 않는다. 녹음 시작은 녹음 탭에서만 제공한다.

원본 HTML의 `tabs` 배열, [UI_REFERENCE](../reference/UI_REFERENCE.md)와
[팔레트](../reference/ui_reference_palette.json)를 대조했다.
원본 HTML SHA-256은 `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555`다.
원본 자료는 수정하지 않았다.

## 구현

| 파일 | 변경 |
|---|---|
| `lib/app/app_tab.dart` | 설계서 순서의 5개 탭 이름·아이콘 |
| `lib/app/app_shell.dart` | 내 곡으로 시작, 공통 상단 설정과 하단 5개 탭, 방문한 탭 유지 |
| `lib/app/song_record_app.dart` | 기본 경로를 앱 탐색 골격에 연결, 설정과 dev 진단 경로 등록 |
| `lib/routing/app_routes.dart` | `/settings`, `/dev/health` 경로 |
| `lib/features/settings/settings_screen.dart` | 설정 진입·뒤로가기·dev 진단 메뉴 |
| `lib/features/health/health_screen.dart` | 녹음 패널 제거, 서버 연결 진단 역할 유지 |
| `test/app_shell_test.dart` | 탭·설정 복귀·자동 녹음 방지·녹음 상태 유지·환경별 진단 노출 검사 |
| `test/widget_test.dart` | 기존 테마·녹음·health 검사를 새 실제 진입 경로로 조정 |

경로는 `apps/mobile/` 기준이다.

- 기본 화면은 내 곡이다. 시작 화면에서 health 요청이나 녹음 패널 초기화를 하지 않는다.
- 방문한 탭은 `IndexedStack`에 유지하고 숨은 탭의 키보드 초점과 애니메이션을 제외한다.
  탭 전환 시 현재 초점을 해제한다.
- 녹음 탭 첫 방문 시 기존 `RecorderPanel`을 연결하고 이후 탭/설정 이동에서도 같은 State를 유지한다.
  서비스 상태의 이벤트와 기존 조회 로직은 계속 사용한다. 이동 콜백에서 녹음 시작·종료를 호출하지 않는다.
- 설정은 루트 Navigator에 별도 화면으로 올린다. 상단 뒤로가기와 Android 뒤로가기 모두
  기존 탭으로 돌아오며 선택 탭을 내 곡으로 강제 변경하지 않는다.
- 서버 연결 확인은 dev 설정 메뉴에서 연다. 메뉴와 라우트 모두 staging/prod에서 제외했다.
- 공통 테마의 초기 블루·선택 아이콘 대비·76 높이·44 이상 설정 조작 크기를 사용한다.
  SafeArea로 가로 시스템 여백을 반영하며 하단 안전 여백은 NavigationBar가 처리한다.
- 내 곡·차트·플레이리스트·검색과 일반 설정 기능은 준비 안내만 표시한다.
  데이터 미연결 상태를 실제 빈 계정이나 성공한 검색 결과로 표시하지 않는다.

## 구현 경계

이번 단계는 탐색 골격이다. 탭별 상세 Navigator, 원래 목록과 선택한 플레이리스트 문맥 복원은
P05-03이며 화면 기능·설정 영속 저장·인증·외부 검색·차트 데이터는 각 후속 단계다.
탭 루트에서 Android 뒤로가기를 누르면 현재 플랫폼의 기본 동작을 따른다.

기존 RecorderPanel·RecorderGateway·Android 서비스 구현과 파일 저장 경로는 변경하지 않았다.
녹음 탭의 패널은 기존 P02 시제품이며 최종 P18 녹음 화면이나 P04 계정 DB 연결 완료를 의미하지 않는다.
SQL V1~V7, Drift 스키마, 의존성 및 flavor·API 주소 설정도 변경하지 않았다.

## 검증 상태

| 확인 | 결과 |
|---|---|
| GitHub 기준 파일의 Git blob 일치 | 확인 |
| 원본 설계서·계획서·HTML 탭 순서 및 설정/녹음 진입 대조 | 확인 |
| 패치 LF/CRLF 적용과 결과 파일 일치 | 두 줄바꿈 방식에서 적용·결과 일치 확인 |
| 기존 파일 충돌 시 패치 덮어쓰기 방지 | 새 파일/기존 수정 충돌 모두 거절, 부분 적용 없음 확인 |
| 사용자 노트북 `flutter analyze` | `No issues found!` (1.9초) |
| 사용자 노트북 `flutter test` | 66개 통과·건너뜀 0개·실패 0개 |
| Android 새 골격 실행·설정 복귀·녹음 중 탭 이동·종료·재생 | 사용자가 모두 정상 동작 확인 |
| 이번 변경 커밋 CI·APK | `46f471e`, CI 35736145931 전체 성공 |

새 위젯 테스트 3개를 포함한 전체 66개가 사용자 노트북에서 통과했다. 새 검사는 다음 행동을 확인한다.

1. 5개 탭 이름·순서·선택 화면과 모든 탭에서 설정 복귀. 이동 중 권한 요청·녹음 시작·종료·health 호출 없음.
2. 녹음 시작 후 검색/설정 이동과 복귀. 같은 패널/구독에서 갱신된 시간과 녹음 ID를 유지하고 명시적 종료만 수행.
3. 서버 확인은 dev 설정에서만 노출·요청하며 서버 확인 화면에 녹음 조작이 없음.

기존 테마 검사는 실제 새 녹음 탭으로, 기존 health 성공·실패 검사는 설정의 진단 경로로 진입한다.
권한 거절·재허용·상태 조회·복구·6분 제한 등 기존 RecorderPanel 단위 검사는 유지한다.
가짜 gateway를 사용하는 위젯 검사가 Android 실제 녹음·재생 검사를 대신하지 않는다.

## 2026-09-22 사용자 실행 결과

사용자 Windows 노트북의 `C:/Users/ksh/Documents/GitHub/Song_Record`에서 패치를 적용했다.
Dart 포맷은 8개 파일 중 4개를 정리했고, 분석은 문제 없음, 전체 테스트는 66개 모두 통과했다.
이 작성 환경에서 실행한 결과가 아니라 사용자가 보낸 명령 출력으로 확인한 결과다.

SM A546S / Android 16의 첫 화면 캡처에서 내 곡 선택, 초기 블루, 오른쪽 위 설정 버튼과
설계 순서의 하단 5개 탭을 확인했다. 보이는 범위에서 탭 이름이 잘리지 않는다.
사용자는 각 탭의 설정 진입·상단/Android 뒤로가기, 녹음 탭에서 시작한 뒤 다른 탭과 설정을
다녀와도 녹음 상태·시간 유지, 명시적 종료와 재생까지 모두 정상이라고 확인했다.
동작 결과는 사용자 보고이며 한 장의 첫 화면 캡처로 녹음 동작을 직접 관측한 것은 아니다.

이번 확인은 P05-02의 탐색과 짧은 녹음 이동 검사다. 전체 P02/P18 녹음 검증이나
P05-08의 작은 화면·큰 글꼴·전체 접근성 검수 완료를 뜻하지 않는다.
코드·문서 12개 반영과 해당 커밋의 새 CI 전체 성공을 확인했다.
기기 전환 중 APK 서명 불일치가 보고됐으며, 이후 사용자가 앱의 모든 검사 동작이 정상임을 다시 확인했다.
서명 키 공유나 삭제 성공 명령 출력까지 확인한 것으로 기록하지 않는다.

## 사용자 PC 확인

저장소 루트에서 패치를 적용한 뒤 `apps/mobile`에서 실행한다.

```powershell
dart format lib/app lib/routing lib/features/health lib/features/settings test/app_shell_test.dart test/widget_test.dart
flutter analyze
flutter test
```

Android Studio에서 Dart entrypoint를 `lib/main.dart`로 되돌리고 기존 flavor·환경·API 주소 인자를 유지한다.
또는 연결 기기를 선택해 실행한다.

```powershell
flutter run --debug --flavor dev --dart-define=APP_ENV=dev -t lib/main.dart
```

- 처음 내 곡이 열리고 하단 탭 5개가 지정 순서로 보이는지 확인한다.
- 각 탭에서 설정을 열고 상단/Android 뒤로가기로 같은 탭에 돌아오는지 확인한다.
- 녹음 시작 버튼이 녹음 탭에서만 보이는지, 다른 탭을 눌렀을 때 자동 녹음하지 않는지 확인한다.
- 짧은 새 테스트 녹음을 시작한 뒤 다른 탭과 설정을 다녀와서 녹음 탭의 경과 시간·상태를 확인하고 종료한다.
- 서버 연결 확인이 필요하면 기존 서버·USB 매핑·API 주소를 사용해 dev 설정의 개발 도구에서 연다.

## Flutter API 근거

탭 유지 구조는 [IndexedStack](https://api.flutter.dev/flutter/widgets/IndexedStack-class.html),
하단 탭은 [NavigationBar](https://api.flutter.dev/flutter/material/NavigationBar-class.html),
숨은 탭 초점 제어는 [ExcludeFocus](https://api.flutter.dev/flutter/widgets/ExcludeFocus-class.html)를 사용한다.
