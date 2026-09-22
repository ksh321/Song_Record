# P05-01 색상과 치수 토큰

2026-09-22. 기준 커밋 `64b6284b835949d6a9f517aaeebd59716ee972e6`.
상태: **구현·Windows 분석/테스트·Android 화이트 테마 화면 확인 / 나머지 수동 확인·커밋·CI 대기**.

## 근거와 완료 조건

- 코드구현계획서 v1.0의 P05-01: 배경·표면·본문·간격·글자·치수 토큰, 초기 블루,
  8개 강조색, 흰색 강조색의 검정 글자, 녹음 전용 빨강.
- [팔레트](../reference/ui_reference_palette.json)와 [UI 기준](../reference/UI_REFERENCE.md).
- 원본 HTML SHA-256:
  `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555`.
- 첨부 JSON/UI_REFERENCE의 Git blob이 저장소 원본과 같음을 확인했다.
  원본 DOCX·HTML·MD·JSON은 수정하지 않았다.

## 구현

| 파일 | 역할 |
|---|---|
| `lib/core/theme/app_tokens.dart` | 8개 강조색 enum, 의미별 색상, 글자·치수·간격 상수 |
| `lib/core/theme/app_theme.dart` | 정확한 색상의 Material 3 다크 테마와 녹음 버튼 스타일 |
| `lib/app/song_record_app.dart` | 기본 블루 연결, 선택 강조색을 생성자 인자로 주입 |
| `lib/features/recorder/recorder_panel.dart` | 기존 시작·종료 버튼의 색상만 공통 녹음 스타일로 연결 |
| `tool/preview_theme.dart` | debug/dev 전용 8개 강조색 수동 검수 화면 |
| `test/theme_contract_test.dart` | 원본 JSON 기준 색상·버튼 상태·큰 글꼴 높이 검사 |
| `test/widget_test.dart` | 실제 앱 기본 테마와 8가지 강조색에서 녹음 버튼 연결 검사 추가 |

경로는 별도 표시가 없으면 `apps/mobile/` 기준이다.

- `AppAccent.initial`은 `blue`다. 이름이 ‘기본값’인 회색은 `neutral`, 저장 식별자는
  원본대로 `default`이며 초기값과 구분했다.
- `ColorScheme`에 명시 색상을 넣는다. Material seed 색 생성이나 표면 tint가
  원본 배경·카드·강조색을 바꾸지 않게 했다.
- 흰색 강조색의 주요 버튼과 선택 내비게이션 아이콘은 검정이다.
- 활성 녹음 시작 배경과 종료 글자·테두리는 항상 `#E5484D`다. 비활성 상태는
  raised/muted로 구분하고 기존 권한·시작·종료·복구 동작은 유지한다.
- 기본 버튼은 최소 52, 아이콘 조작은 최소 44다. 버튼에 고정 최대 높이를 주지 않아
  큰 글꼴에서 높이가 늘어날 수 있다. 시스템 글자 배율을 강제로 줄이지 않는다.
- 필드 최소 71·둥글기 9, 카드 둥글기 22, 시트 둥글기 25·배경·오버레이,
  내비게이션 높이 76을 공통 테마에 연결했다. 필드 안쪽 여백은 최종 HTML의 12/15다.
- 390×844 검수 프레임을 앱 크기 상수로 옮기지 않았다.
- 키 배지와 기록 빨강 등 의미 색은 강조색과 독립적이다. 키·티어·행·시트의 나머지
  측정값은 다음 P05 구성요소에서 사용할 토큰으로 마련했다.
- 글꼴은 참조 순서의 fallback만 설정했다. HTML의 포함 폰트를 추출·배포하지 않았다.
  해당 폰트가 없는 기기에서는 시스템 폰트가 사용되므로 글리프·행 높이는 실기 대조가 필요하다.
- 설정 화면 및 강조색 저장은 아직 연결하지 않았다. 현재 앱의 기본 진입점은 계속
  `lib/main.dart`이며 상단/하단 탐색은 P05-02 범위다.
- 녹음 원형/정지 사각형 치수는 토큰만 추가했다. P02 시제품 버튼 모양을 최종 녹음
  화면 전체 구현으로 기록하지 않는다.

## 확인 상태

| 확인 | 결과 |
|---|---|
| 기준 main·첨부 원본 해시 | 확인 |
| 원본 JSON의 강조색·의미 색상·글자·컴포넌트 치수와 코드 값 대조 | 수행 |
| 패치의 LF/CRLF 기준 작업본 적용, 변경 파일 대조 | 수행 |
| 기존 파일 충돌 시 무리하게 덮어쓰지 않는 적용 확인 | 수행 |
| 사용자 Windows `dart format` | 7개 파일 검사, 6개 파일 형식 정리 |
| 사용자 Windows `flutter analyze` | `No issues found!` (1.4초) |
| 사용자 Windows `flutter test` | 62개 통과·1개 건너뜀·실패 0개 |
| Android 테마 미리보기 실행 | 사용자 실기 화면으로 실행 확인 |
| Android 화이트 강조색 | 주요 버튼 검정 글자, 녹음 빨강, 키 배지, 긴 문장 줄바꿈 확인 |
| 모든 강조색 전환·키보드 표시·시스템 큰 글꼴 수동 확인 | 이번 캡처로 확인하지 못함 |
| 이번 변경 커밋의 GitHub CI·CI Android APK | 확인 대기 |

값·패치 대조는 Python과 Git으로 수행하며 Flutter 타입 검사나 렌더링 검사를 대신하지 않는다.
Flutter 분석·테스트 결과는 사용자가 Windows PC에서 실행한 출력으로 확인했다.
건너뛴 1개는 기존 계정 저장소 테스트의 심볼릭 링크 사례다. Windows 링크 생성 권한이 없어
건너뛰었으며, 이번 변경의 Ubuntu CI 결과를 별도로 확인한다.
기준 커밋의 [CI 35704893355](https://github.com/ksh321/Song_Record/actions/runs/35704893355)는
전체 성공했지만 이 P05-01 변경의 검사 결과는 아니다.

### 2026-09-22 사용자 실기 화면

앞서 연결을 확인한 SM A546S / Android 16에서 테마 미리보기를 실행한 화면을 받았다.
캡처에는 ‘선택한 강조색: 화이트’와 흰색 주요 버튼·검정 글자, 회색 비활성 버튼,
빨간 녹음 시작 버튼·종료 테두리, 원키·남·여 키 배지가 표시된다.
긴 설명은 두 줄로 표시되고, 보이는 카드 안에서 글자나 버튼이 잘리지 않는다.
입력 필드에 글자와 커서가 보이지만 키보드는 표시되지 않은 상태다.

초기 블루와 8개 강조색 값·각 강조색에서 실제 녹음 버튼의 빨강 유지는 자동 테스트에서
확인했다. 한 장의 캡처를 8개 색상의 수동 전환이나 키보드·큰 글꼴 검수 완료로 기록하지 않는다.
미리보기의 녹음 버튼은 모양 확인용이며 실제 녹음·재생을 검사한 결과가 아니다.

## 사용자 PC 검증

패치를 저장소 루트에 적용한 뒤 `apps/mobile`에서 실행한다.

```powershell
dart format lib/core/theme lib/app/song_record_app.dart lib/features/recorder/recorder_panel.dart tool/preview_theme.dart test/theme_contract_test.dart test/widget_test.dart
flutter analyze
flutter test
```

8가지 강조색을 확인할 때는 실제 연결된 기기를 선택해 실행한다.

```powershell
flutter run --debug --flavor dev -t tool/preview_theme.dart
```

- 최초 블루, 8개 이름과 색, 흰색 선택 시 주요 버튼 검정 글자.
- 각 강조색에서 녹음 빨강과 세 키 배지 색 유지.
- 비활성 버튼, 긴 제목, 시스템 큰 글꼴, 키보드에서 스크롤 확인.
- 미리보기는 검수용이며 서버·계정 DB·마이크를 호출하지 않는다. 강조색 선택은
  해당 실행 동안만 유지하며 제품 설정에 저장하지 않는다.
- 검수 뒤 기존 Android Studio 실행 설정에서 `lib/main.dart`로 돌아가고 기존
  `--flavor dev`, `APP_ENV`, `API_BASE_URL` 인자를 유지한다.

Windows 분석·테스트와 위 화이트 테마 실기 확인은 완료했다. 나머지 수동 확인과
해당 변경 커밋의 CI 결과를 확인한 뒤 완료 상태를 갱신한다.
P05-02~08의 탐색 스택·공통 행·시트·키 선택기·접근성 전체 검수를 완료한 것은 아니다.

## 사용 API 근거

[ThemeData](https://api.flutter.dev/flutter/material/ThemeData-class.html),
[ColorScheme.dark](https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.dark.html),
[FilledButton.styleFrom](https://api.flutter.dev/flutter/material/FilledButton/styleFrom.html),
[BottomSheetThemeData](https://api.flutter.dev/flutter/material/BottomSheetThemeData/BottomSheetThemeData.html).
