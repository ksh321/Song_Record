# P05-05 공통 선택 시트

기준 커밋: `4d23c8d5c3896789d6204e6396a9f1ee981730a6`.
상태: **구현·샘플 실기 확인 / 테스트 최종 종료·커밋·새 CI 확인 대기**.

## 범위와 근거

코드구현계획서 P05-05의 SortSheet·TierPicker·VersionPicker를 구현한다.
UI_REFERENCE의 정렬 항목, 티어 안내·순서, 선택 체크, 배경·높이·모션 규칙과
HTML의 공통 선택 시트 상호작용을 따른다. 원본 설계 자료는 변경하지 않는다.

- 내 곡 정렬: 최근 추가순, 최근 녹음순, 티어순, 곡명순, 가수순.
- 녹음 정렬: 최신순, 오래된순, 곡명순, 티어순.
- 곡 티어와 녹음 티어는 별도 도메인 타입을 사용하고 평가 대상 안내를 구분한다.
- S → A → B → C → D → 미정. 여섯 항목 모두 설명을 제공한다.
- 버전은 일반 반주 / MR / LIVE. 기본값은 호출자가 VersionCode.normal로 전달한다.
- 현재 값은 체크 아이콘과 선택 접근성 정보로 표현한다. 색상만으로 구분하지 않는다.
- 시트 배경 #232323, 검정 48% 오버레이, 상단 모서리 25, 최대 화면 높이 90%.
- 진입·퇴장 180ms. 모션 감소 또는 accessibleNavigation에서는 애니메이션을 끈다.
- SafeArea와 스크롤로 작은 화면·큰 글꼴에서 모든 선택지와 취소에 접근한다.

## 결과와 취소 계약

선택 행을 누르면 즉시 닫히고 `SelectionResult<T>`를 반환한다.
취소 버튼·바깥 영역·뒤로가기·아래로 끌어 닫기는 route 결과 null이다.
명시적 미정 선택은 `SelectionResult<SongTier?>(null)` 또는 녹음 타입의 동일한 결과다.
따라서 호출자는 `result != null`일 때만 result.value를 반영한다.
값 자체가 null인지로 취소를 판정하면 미정 선택을 놓치므로 그렇게 사용하지 않는다.
미리보기는 이 계약을 사용하며 취소 시 이전 값을 유지한다.

공통 함수는 선택지 중복·빈 목록·현재 값 누락을 거절한다. Root Navigator에 시트를 열어
탭 골격 위에서 선택하고, 시트 내부 context로 pop하여 원래 화면을 보존한다.

## 검증

작성 환경에 Flutter/Dart SDK가 없으므로 실행 성공을 주장하지 않는다.
추가한 selection_sheets_test.dart는 다음 여섯 검사를 담는다.

1. 내 곡/녹음 정렬 항목 구분 및 선택 결과.
2. 티어 설명과 현재 체크, 미정 선택과 취소 결과 구분.
3. 녹음 전용 안내와 RecordingTier 반환.
4. 버전 세 항목과 결과.
5. 바깥 터치·시스템 뒤로가기 취소.
6. 320×640, 글꼴 1/2/3배의 최대 높이·스크롤 취소·모션 감소.

```powershell
dart format lib/core/widgets/selection_sheet.dart lib/core/widgets/sort_sheet.dart lib/core/widgets/tier_picker.dart lib/core/widgets/version_picker.dart tool/preview_selection_sheets.dart test/selection_sheets_test.dart
flutter analyze
flutter test
flutter run -d R5CW618VA1M --debug --flavor dev -t tool/preview_selection_sheets.dart
```

미리보기 제목: 공통 선택창 미리보기. 샘플 곡 3개·녹음 3개를 표시한다.
정렬 선택은 샘플 순서를 바꾸고 각 카드의 티어·버전 버튼은 해당 샘플만 변경한다.
곡 버전 변경은 기존 녹음 버전에 전파하지 않는다. 취소는 기존 값을 유지한다.
사용자 요청으로 큰 글자 2배·모션 감소 스위치는 제거했다. 시스템 접근성 대응은 유지한다.

### 사용자 결과

- 수정 전 공통 시트 분석은 No issues found. 전체 테스트 출력은 +84까지 확인했다.
  최종 All tests passed 문구와 종료 상태는 아직 전달받지 않아 전체 종료 성공으로 단정하지 않는다.
- 샘플을 추가하고 스위치를 제거한 미리보기는 사용자가 정상 작동함을 보고했다.
- 최근 추가순: 바람 → 노을 → 가을, 곡명순: 가을 → 노을 → 바람.
  초기 티어순: 가을 A → 바람 B → 노을 미정. 바람을 S로 바꾸면 맨 위로 이동한다.
- 수정본 분석의 별도 출력과 해당 커밋 CI는 확인 대기다.

## 구현 경계

공통 코드는 선택 UI와 결과 전달을 구현한다. 별도 미리보기에서만 메모리 샘플의 정렬·값 변경을 수행한다. 실제 목록 정렬·DB 저장·서버 변경·녹음 수정은 후속 연결이다.
기본 앱에는 샘플이나 임시 저장을 연결하지 않는다. 그룹 안 정렬은 실제 티어 그룹 화면 연결 시
해당 화면의 허용 항목으로 별도 구성해야 한다. 키 선택기는 P05-06에서 다룬다.

공식 API 근거: https://api.flutter.dev/flutter/material/showModalBottomSheet.html
