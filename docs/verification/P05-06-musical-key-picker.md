# P05-06 키 선택기

기준 커밋: `566ae21013841b6591d3e0c57cb9bb394857e5f5`.
상태: **구현·사용자 검증·main 반영·해당 커밋 CI 완료**.
반영 커밋: `ff82c93f54a114332898dd65808229fdbe8aba47`.
[CI 35846248525](https://github.com/ksh321/Song_Record/actions/runs/35846248525)의 Flutter/Android, Spring Boot, MySQL 세 작업 모두 성공했다.

## 설계와 동작

구현설계서 v1.11의 키 모드·반음 저장 규칙, 코드구현계획서 P05-06,
UI_REFERENCE의 키 선택 항목과 HTML의 선택 시트 동작을 따른다.

- 곡 대표 키와 녹음 키는 같은 키 선택기를 사용한다. 곡은 `미정`을 명시적으로 고를 수
  있지만 녹음에는 미정 버튼이 없고 처음 열 때 `원키`(ORIGINAL/0)로 시작한다.
- 원키/남/여 모드와 −12~+12 반음 휠을 제공한다. 항목 44, 휠 220 높이로
  다섯 칸을 표시하고 끝에서 순환하지 않는다. 각 칸은 반음 하나다.
- 원키 0은 `원키`, 원키 +1은 `원키 +1`, 남 0은 `남 0`처럼 표시한다.
  모드 변경은 반음 값을 자동 환산하거나 초기화하지 않는다.
- 휠과 모드 조작은 시트 내부의 임시 선택이다. `적용`을 누를 때만 결과를 반환하고,
  취소·시트 바깥 터치·기기 뒤로가기는 결과 없이 닫아 호출자의 값을 유지한다.
  `미정으로 두기`는 취소와 달리 `SelectionResult<MusicalKey?>(null)`을 반환한다.
- 시트 높이는 화면의 최대 90%로 제한하고 내부 스크롤을 제공한다. 시스템의 모션
  감소 설정에는 시트·휠 이동 애니메이션을 사용하지 않는다.

`MusicalKey`의 기존 원키=0 추가 제한을 제거했다. 원본 설계서는 ORIGINAL과
−12~+12 정수를 함께 저장하도록 정의하고, UI_REFERENCE와 HTML은 원키 +1을
실제 선택 사례로 제시한다. 범위 바깥 값을 거절하는 검증은 유지한다.

## 서버 저장 전 해결할 계약 불일치

서버의 이미 적용된 Flyway `V2__account_song_recording.sql`은 곡 대표 키와 녹음 키
모두 `ORIGINAL`이면 0이어야 한다는 CHECK를 포함한다. 현재 이 화면에서 `원키 +1`을
고르더라도 **서버 DB에는 저장할 수 없다**. P05-06은 독립 컴포넌트와 메모리 샘플이고
실제 저장 화면이나 서버 API에 아직 연결되지 않으므로, 이 차이를 해결하기 전에
원키 비영 값을 서버로 전송하는 흐름을 공개하지 않는다.

서버 연결 작업에 들어가기 전, 적용된 V2 파일을 고치지 않고 **새 Flyway 마이그레이션**에서
`ck_song_representative_key`와 `ck_recording_key`의 원키=0 조건을 제거해야 한다.
모드 3종, −12~+12 범위, 대표 키 두 필드의 함께 NULL 규칙, SAVED 녹음 키 필수 규칙은
유지한다. 새 DB와 기존 V7에서 업그레이드한 DB 모두에 대해 ORIGINAL ±1 저장,
범위 밖 거절, 기존 데이터 및 Flyway 재시작 검증을 수행한 뒤 실제 저장 UI를 연결한다.

## 사용자 검증

사용자 노트북에서 수정 패치 적용 후 Flutter 분석 및 키 선택기·전체 테스트가 모두
통과했다는 보고를 받았다. 이어서 SM A546S의 미리보기 실기 확인도 이상 없음으로
보고받았다. 실행은 사용자가 수행했으며, 작성 환경에서 직접 재실행한 결과는 아니다.
2026-09-23에 해당 커밋의 push CI 세 작업 성공을 확인했다.

초기 패치의 오류 두 건을 수정했다. `const Semantics`의 잘못된 const를 제거했고,
접근성 증감 동작에 `increasedValue`·`decreasedValue`를 추가했다. −12/+12 끝에서는
범위를 벗어나는 방향의 접근성 동작을 비활성화했다. 최초 실패 로그를 통과로
기록하지 않으며, 위 완료 상태는 두 수정 뒤의 사용자 재검증 보고를 기준으로 한다.

`test/musical_key_picker_test.dart`의 검증 범위는 다음과 같다.

1. 원키 ±12의 도메인 표시와 범위 바깥 거절.
2. +12 선택과 모드 변경 시 값 유지, 적용 결과.
3. 휠 끝의 비순환 동작과 원키 −12 적용.
4. 취소와 명시적 미정 선택 구분, 기존 선택값 유지.
5. 녹음 키의 기본 원키와 미정 버튼 부재.
6. 320×640, 글꼴 2배에서 시트 스크롤과 적용 버튼 접근.
7. 샘플에서 곡 대표 키 변경 후 이전 녹음 보존과 새 녹음 기본값 복사.

노트북에서 저장소 루트 `C:/Users/ksh/Documents/GitHub/Song_Record`로 이동해
패치를 적용한 뒤, `apps/mobile`에서 실행한다.

```powershell
dart format lib/core/domain/song_types.dart lib/core/widgets/musical_key_picker.dart tool/preview_musical_key_picker.dart test/musical_key_picker_test.dart
flutter analyze
flutter test
flutter run -d R5CW618VA1M --debug --flavor dev -t tool/preview_musical_key_picker.dart
```

미리보기의 두 곡과 두 과거 녹음은 메모리 샘플이다. `아침 노래`의 대표 키를
`원키 +1`로 바꾼 후 `아침 노래 · 지난 녹음`이 여전히 `원키`인지 확인한다.
`곡의 현재 대표 키 채우기`를 누르면 새 녹음의 값만 `원키 +1`로 바뀐다.
`미정으로 두기`와 `취소`의 차이, 남/여 모드 변경 중 반음 유지, −12/+12 끝값,
녹음 선택기에 미정 버튼이 없는지도 확인한다. 샘플은 앱의 실제 곡과 녹음에
영향을 주지 않는다.

공식 Flutter API: https://api.flutter.dev/flutter/widgets/ListWheelScrollView-class.html,
https://api.flutter.dev/flutter/widgets/FixedExtentScrollController-class.html,
https://api.flutter.dev/flutter/material/showModalBottomSheet.html.
