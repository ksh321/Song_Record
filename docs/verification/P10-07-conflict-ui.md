# P10-07 — 3방향 충돌 처리: 선택 화면 연결

2026-10-01. R038, plan.txt p00593~p00595, design.txt p00300~p00305, 원본 HTML conflict/conflict-server 화면(검색 HTML392~393행), UI_REFERENCE와 기존 AppTokens 기준.

## 원본 작업 기준 현재 범위

- 기존 등록 a~c는 비교, d~g는 원본/전송 순서/선택/트랜잭션, h는 이번 화면 연결이다. 원본 계획서 작업이 추가된 것이 아니다. 2026-10-01 후속 사용자 지시에 따라 이 세부 ID와 남은 범위는 그대로 유지한다. 앞으로 새로 등록하는 작업부터 원본 번호로 묶으며 기존 작업은 소급 통합하지 않는다. 전체 P10-07 완료 조건 충족 여부도 별도로 구분한다.
- 동기화 상태의 ‘변경 검토’에서 서버 값과 이 기기 입력을 나란히 확인하고 명시적으로 사용할 쪽을 선택한다. 결합 필드는 같은 쪽으로 선택하며 충돌하지 않은 수정은 유지한다. 선택 없이 뒤로 가면 저장하지 않는다.
- 서버 선택/로컬 선택 뒤 저장 중 중복 누름을 막고, 변경된 근거나 저장 실패는 성공으로 표시하지 않는다. 원본 요청과 모든 이력은 복구 데이터에 남기고 유효하게 해결된 원본만 작업 목록에서 제외한다.
- 태그는 당시 이름 또는 현재 계정의 로컬 태그 이름으로 표시한다. 이름을 찾지 못하면 의미를 알 수 없는 ID를 선택시키지 않고 입력을 보존한다. 누락 이름 수신 보완은 남은 수신 작업과 연결된다.
- 계정 전환은 기존 LoginGate의 계정별 앱 트리 키로 화면을 분리하고 AccountStore가 읽기/저장 시 계정을 재검사한다. 선택 화면이 새 전송 루프를 만들지 않으며 기존 컨트롤러의 인증 차단·활성 상태를 확인한 뒤 깨운다.

## 실제 검증과 현재 모델 코드 검토

- `flutter test --no-pub test/conflict_screen_test.dart test/sync_controller_test.dart test/conflict_resolution_store_test.dart`: **46 PASS**.
- 태그 이름/누락 처리와 저장소 작업 목록 연결 추가 후 `flutter test --no-pub test/conflict_screen_test.dart test/conflict_resolution_store_test.dart`: **19 PASS**.
- 변경 AccountStore/LocalRepository/ConflictReview/동기화 화면·컨트롤러/main 및 테스트 분석: 경고/스타일 보완 후 **No issues found**. `git diff --check` 통과.
- 실제 소스·diff·원본 HTML과 비교: 명시 선택 전 양쪽 입력 보존, 두 번 누름1회, 서버/로컬 선택, 실패 후 새 검토, 태그 이름 표시, 해결 이력 보존, 기존 컨트롤러 회귀. 다른 에이전트 검수라고 부르지 않는다.
- 로그 `.local/workflow/p10-07-ui-{test,review}.log`. 기존 폰 USER-025는 c7df3fd에 대한 확인이며 이번 변경으로 확대하지 않는다. 새 APK 설치나 두 기기 V25 실기 수행은 아직 기록하지 않는다.

## 남은 조건

통합 SHA 필수 CI 확인, 최신 서버 사본/삭제 수신과 통합 확인, P10-10의 두 기기 V25 시나리오. 이 문서는 UI 구현 검증이며 전체 P10 단계나 두 기기 실기 완료 선언이 아니다. P10-06 미구현 수신 범위를 이어서 처리한다. 모델/속도 자동 변경은 확인되지 않아 주장하지 않는다.

D06 표시명 재대조 보완: BAD의 승인된 화면 이름은 ‘안 좋음’이다. 새 충돌 화면도 동일하게 수정했다. `flutter test --no-pub test/conflict_screen_test.dart` 8 PASS, 화면/테스트 분석 No issues found. 제품 단계 추가가 아닌 P10-07의 표시 보완이며 추가 세부 ID를 만들지 않는다.

### 2026-10-07 USER-036 판본2 휴대폰 설치

최신 verification/debug 앱을 tool/sync_verification.dart로 빌드했다. 기존 폰 검증 앱과 서명이 달라 데이터 삭제 없이 .verification.laptop 패키지(노래기록 동기화 검증 노트북)로 별도 설치했다. 패키지명/표시명만 빌드 중 변경했고 Gradle 원본 바이트 복원 및 검토된 소스 지문 일치를 확인했다. adb install Success, activity 시작 접수, 설치 package 경로 확인. APK SHA256: 8824380b28ef2325ae0eef60e088e95165cdad49815e4ad67183b6d51d56b272. 실기 완료로 판정하지 않으며 구체 순서는 내가할일.md USER-036 판본2에 기록했다.

### USER-036 판본2 결과 및 커밋 소유 목록 보정

사용자가 1~5 모두 성공했다고 확인했다. 앞선 대기는 서버 값 사용 버튼을 잘못 선택한 경우로 정정됐다. 설치 소스 지문 일치·로컬 검사12항목 PASS·현재 모델 검토 승인·실기 통과를 대조했다. COMMIT에서 발견한 v9 DB/생성 파일/회귀 fixture의 계획 소유 목록 누락9개를 실제 검증·검토된 파일로 보정했다. 제품 코드나 검증 기준을 바꾸지 않았고 사용자 요청 USER-037은 AI 해결로 종료했다.
