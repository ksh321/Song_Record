# 노래기록앱 구현 진행 기록

- 기록 버전: 2.6
- 작성일: 2026-09-17
- 기준: 구현설계서 v1.11 / 코드구현계획서 v1.0
- 요구사항: [requirements.md](requirements.md)
- 권장 위치: `docs/progress.md`
- 주의: 기존 진행 파일이 있다면 덮어쓰지 말고 이번 기록을 합친다.

## 1. 현재 상태

P00-01 기준 파일 등록, P00-02 요구사항 목록 만들기, P00-04 구현 기술 결정과 P00-05 정렬과 필터 계약, P00-06 입력과 누락 API 계약, P00-07 스냅샷과 백업 계약을 완료했다. GitHub main에서 기준 파일 위치·원본 동일성·README와 요구사항/진행 문서의 원격 반영을 확인했다. Flutter 빈 앱 생성과 실제 Android 기기 실행, 정적 분석 및 기본 위젯 테스트를 확인했다. Spring Boot 4.1.1 프로젝트와 Java 21·Gradle 9.7.1 도구 확인 및 DB 없는 bootstrap 기동 구성을 반영했다. Windows 11에서 clean test와 bootstrap 서버 기동을 확인해 P01-03을 완료했다. P01-04용 MySQL 8.4.11 digest 고정 Compose와 Spring dev 프로필을 반영하고 로컬 연결·영속성 검증까지 완료했다. P01-05 Flyway 최초 마이그레이션과 스키마 검증 설정을 반영하고 로컬 첫 기동·재기동을 모두 확인했다. P01-06 Flutter health 호출 화면과 실제 기기 USB 주소 연결을 구현했으며 실기 검증을 기다린다. 녹음 기능 실기 테스트는 아직 수행하지 않았다.

| 작업 | 상태                    | 확인 내용 | 남은 확인 |
|---|-----------------------|---|---|
| P00-01 기준 파일 등록 | 완료 | docs/reference 원본 5개·Git blob 동일성·README 버전/해시/역할·대응 관계 확인 | 없음 |
| P00-02 요구사항 목록 만들기 | 완료 | R001~R128, V01~V48, X01~X12, C01~C16, D01~D11 매핑 및 docs 원격 반영·검토 완료 | 없음. 앱 구현·검증은 후속 작업 |
| P00-03 외부 데이터 선행 조사 | 기술 조사·채택 완료 / 이용 조건 확인 대기 | Manana TJ/KY × daily/weekly/monthly 6개 HTTP 200·각 100곡, D12 확정 | 상업적 표시·저장·캐시 허용 조건 및 기간 집계/최신성 확인 |
| P00-04 구현 기술 결정 | 완료 | 사용자 A안 승인, D01 결정서·초기 버전 기준·고정 대상·공식 요구 조건 대조 | 실제 의존성 해결·빌드·lock 생성은 P01, 녹음 실기 채택은 P02 |
| P00-05 정렬과 필터 계약 | 완료 | D02~D04 추천 조합 승인·정렬/날짜/파일 필터/페이징 계약·공통 기대 사례 기록 | 앱·서버 시제품 및 V/X 실행은 P03·P07·P08·P09·P14·P18, 전체 fixture 통합은 P00-08 |
| P00-06 입력과 누락 API 계약 | 완료 | D05~D08·공통 사례·요구사항·README 반영. 사용자 선택 구체화 | 실제 입력/API/DB/화면 검증은 후속 구현 단계 |
| P00-07 스냅샷과 백업 계약 | 완료 | D09~D11 추천 A안 승인·만료/재개/인증/완료 표시·공통 사례 반영 | 구현 검증은 P07·P10·P21·P22·P23·P24, fixture 통합은 P00-08 |
| P00-08 공통 검증 데이터 작성 | 완료(산출물) | JSON 169사례·합성 파일 3개·참조 대조 31건 | 앱/서버 로더 P01/P03, 통합 명세 138건 후속 실행 |
| P01-01 저장소 구조 만들기 | 완료 | apps/mobile·services/api·infra·README·설정 예시·Git 제외 규칙 | 없음. 프로젝트 생성·실행은 후속 작업 |
| P01-02 Flutter 프로젝트 생성 | 완료 | Flutter 3.47.4/Dart 3.13.3, Android dev/staging/prod flavor, 앱 ID·초기 라우트·분석 규칙·lockfile 반영 | 없음. 서버 작업은 P01-03에서 별도 추적 |
| P01-03 Spring Boot 프로젝트 생성 | 완료 | Boot 4.1.1·Java 21·Gradle 9.7.1, 필수 의존성, bootstrap 프로필, clean test·Tomcat 8080 기동 성공 | DB 연결은 P01-04, Flyway 실행은 P01-05. 로컬 생성 gradle.lockfile은 원격 추적 필요 |
| P01-04 MySQL 개발 DB 준비 | 완료 | MySQL 8.4.11 digest 고정, 컨테이너 healthy, Spring dev/Hikari 연결, 재시작 후 `id = 1` 유지 및 확인용 테이블 제거 | 없음. Flyway는 P01-05에서 추적 |\n| P01-05 스키마 버전 관리 연결 | 완료 | Flyway V1 적용, 재기동 시 기존 이력·체크섬 검증, Hibernate validate, 서버 정상 기동 확인 | 없음 |\n| P01-06 헬스 조회 연결 | 검증 대기 | Flutter health 화면·실패/재시도, 공개 health 경로, debug HTTP, 에뮬레이터·실기 주소 문서화 | SM A546S에서 Spring Boot `UP` 응답 표시 확인 |

“수행 기록 없음”은 사용자가 별도로 수행한 작업까지 없었다고 단정하는 상태가 아니다. 증거를 확인하면 갱신한다.

## 2. P00-02 작업 기록

| 항목 | 내용 |
|---|---|
| 목표 | 설계 규칙을 기능·상태·제약·API·검증으로 나누고 기존 작업에 연결 |
| 산출물 | docs/requirements.md, docs/progress.md |
| 원본 수정 | 없음. 구현설계서·HTML·UI_REFERENCE·팔레트·참고 사항·기존 구현계획서 보존 |
| 요구사항 | R001~R128, 각 행에 근거·세부 작업·수용 기준 |
| 필수 검증 매핑 | V01~V48 전체 |
| 추가 검수 매핑 | X01~X12 전체 |
| v1.11 적용 추적 | C01~C16 |
| 미결정 계약 | D01~D11. 제안과 확정 정책 분리 |
| 문서 검증 | 요구사항/검증 ID 연속성·중복·참조 유효성, 작업 ID와 기존 231개 작업 대조 |
| 앱 테스트 결과 | 실행하지 않음 |
| 외부 데이터 조사 | 실행하지 않음. P00-03 및 P16에서 확인 |
| 저장소 커밋 | 기준 파일 이동·문서 등록 확인: [9040547](https://github.com/ksh321/Song_Record/commit/904054792840cbda18daa0f3b70857ecada9f19c); 요구사항 완료 기록: [dd2fb45](https://github.com/ksh321/Song_Record/commit/dd2fb452e9a0be58778ab8c69b2e7a6ad03d69b4) |
| 완료 판단 | P00-02 완료. 요구사항·검증 매핑, 저장소 반영 및 문서 검토 확인. 앱 테스트 통과를 의미하지 않음 |

## 3. 저장소 반영 체크리스트

- [x] requirements.md를 저장소의 docs/requirements.md에 추가
- [x] progress.md를 docs/progress.md에 추가 또는 기존 기록에 병합
- 선택 사항(이번 작업 제외): README에 두 문서의 상대 링크 추가
- [x] docs/reference의 5개 원본과 README 버전·SHA-256·역할 확인
- [x] UI_REFERENCE·팔레트의 HTML 참조 해시가 실제 HTML과 일치하는지 확인
- [x] Git 변경 목록에서 원본 파일의 의도치 않은 수정이 없는지 확인
- [x] 새 문서만 검토 후 커밋하고 아래에 커밋 ID 기록
- [x] 원격 반영이 필요하면 push 후 파일 표시 확인

권장 커밋 메시지: `docs: add P00-02 requirements and progress tracking`

| 저장소 반영 항목 | 값 |
|---|---|
| 검토 기준 커밋 ID | 904054792840cbda18daa0f3b70857ecada9f19c |
| 요구사항 완료 기록 커밋 ID | dd2fb452e9a0be58778ab8c69b2e7a6ad03d69b4 |
| 이 진행 문서의 완료 기록 커밋 | 이 파일의 GitHub History에서 확인 (자기 자신의 커밋 ID를 본문에 기록하지 않음) |
| 검토일·검토자 | 2026-09-16 / Codex 문서·저장소 점검 |
| 원격 반영 | GitHub main의 docs/requirements.md·docs/progress.md 및 docs/reference 원본 5개 확인 |
| P00-02 최종 상태 | 완료 |

## 4. P00-03 조사와 다음 작업

사용자 승인으로 과거 연월 차트를 Manana 일간/주간/월간 인기곡으로 변경했다. [조사 기록](research/external-data.md)과 [D12 변경 계약](decisions/D12-popular-periods.md)을 적용한다.

- 호출: 2026-09-16, TJ/KY × 3개 기간 모두 HTTP 200·각 100곡·브랜드 일치·번호 중복 없음.
- 관측: 약 14~17초, KY daily/weekly 응답 해시 동일. 집계 경계·최신성은 미확인.
- 원본 DOCX/HTML/UI_REFERENCE는 보존하고 차트 관련 충돌은 D12 우선. 요구사항 및 README에 연결했다.
- 이용 조건 확인은 미완료이며 운영 출시 전 확인한다. 실제 제공자에게 문의를 발송한 것은 아니다.
- 기존 완료 월 2개 조사 조건은 폐기했다. P00-04~P00-07 계약 작업을 완료했으며 다음 문서 작업은 P00-08이다.
- API 조사 성공 6건은 V/X 앱 통합 테스트 통과 수에 포함하지 않는다. D12 및 D01~D11은 확정했다. 실제 구현 검증은 별도다.
- 이 변경의 커밋은 이 파일의 GitHub History에서 확인한다.

## 5. 앞으로의 상태 기록 규칙

구현 작업은 `미착수 → 구현 중 → 검증 대기 → 완료`로 관리한다. 문서 작업은 산출물 검토·저장소 반영으로 판정하고, 앱 기능은 코드만 작성했다고 완료로 표시하지 않는다.

- 차단 시 원인·필요 결정·영향 작업·이어 할 독립 작업을 적는다.
- 커밋·테스트 명령/사례·실행 환경·결과·증거 위치를 남긴다.
- 검증 결과는 미실행/통과/실패/차단을 구분한다.
- 실기 검증에는 제조사·기기·OS·앱 버전, 서버 검증에는 서버 버전과 DB/R2 환경을 적는다.
- 테스트 실패 후 원본 음성·사용자 메모·토큰·서명 URL을 로그에 첨부하지 않는다.
- 구현 중 확정 정책이 바뀌면 요구사항과 결정 기록을 먼저 갱신하고 계획서 영향 여부를 검토한다.
- 단순 작업 진행률 갱신은 이 파일에서 관리한다. 기존 계획서 DOCX를 매번 고치지 않는다.

### 작업 기록 양식

| 항목 | 작성할 내용 |
|---|---|
| 작업 ID·이름 | 예: P00-03 외부 데이터 선행 조사 |
| 상태 | 미착수 / 구현 중 / 검증 대기 / 완료 / 차단 |
| 관련 요구사항 | R 번호 |
| 변경 파일 | 저장소 상대 경로 |
| 수행 내용 | 실제 수행한 변경만 기록 |
| 검증 | V/X 번호 또는 자체 수용 기준, 명령·환경 |
| 결과·증거 | 통과/실패/미실행 및 보고서·스크린샷 위치 |
| 커밋 | 실제 커밋 ID |
| 미해결 사항 | D 번호·문제·다음 조치 |
| 다음 작업 | 선행 조건을 만족하는 작업 |

## 6. 검증 현황

| 구분 | 전체 | 실행 | 통과 | 상태 |
|---|---:|---:|---:|---|
| 설계서 V 검증 | 48 | 0 | 0 | 매핑만 완료 |
| 계획서 X 검수 | 12 | 0 | 0 | 매핑만 완료 |
| v1.11 적용 추적 | 16 | 0 | 0 | 관련 R/P/V/X 연결만 완료 |
| D01~D11 결정 기록 | 11 | — | — | D01~D11 확정 11건, 미결정 0건. 테스트 수치와 별도 |

위 수치는 이번 작업에서 확인한 실행 기록 기준이다. 기존 실행 증거가 있다면 중복 실행 대신 먼저 확인하여 반영한다.


## 7. 변경 이력

| 버전 | 날짜 | 내용 |
|---|---|---|
| 1.0.1 | 2026-09-16 | P00-01·02 완료 기록 통일, 체크박스 문법 수정, 실제 기준 커밋·검토 기록 추가. V/X 미실행 및 D 미결정 상태 유지. |

### 1.1 — 2026-09-16

기간별 인기곡 6개 실호출 결과와 D12 사용자 승인 반영. P00-03은 기술 채택 완료/이용 조건 확인 대기로 기록. V/X 테스트 수치는 변경 없음.

### 1.2 — 2026-09-16

P00-04 구현 기술 결정 완료. 사용자 A안 선택을 [D01](decisions/D01-implementation-stack.md)에 기록하고 [버전 기준 및 고정 대상](contracts/toolchain-versions.md)을 추가했다. README와 요구사항의 D01 상태를 함께 갱신했다.

- 검토: 공식 버전·최소 SDK/Java/Gradle 요구 조건, 문서 상대 링크, 기존 요구사항 ID 유지, 원본 파일 보존.
- 범위: 기술 선택과 문서 반영 완료. 앱/서버 프로젝트는 아직 없으며 의존성 해결·호환 빌드·lock 생성은 P01에서 수행한다. V/X 실행 수는 0 유지.
- 후속: P00-05 D02~D04 정렬·필터 계약. P02에서 녹음 플러그인을 실기 검증 후 채택한다.
- 커밋: 이 파일의 GitHub History에서 확인한다.

### 1.3 — 2026-09-16

P00-05 정렬과 필터 계약 완료. 사용자 추천 조합 승인을 반영했다.

- 산출물: [D02 정렬](decisions/D02-sort-order.md), [D03 날짜](decisions/D03-date-boundaries.md), [D04 기기 파일 필터](decisions/D04-device-file-filter.md), [공통 입력·기대 사례](contracts/P00-05-examples.md).
- 결정: 앱 전용 공통 문자열 정렬·숫자 자연순 / 한국 시간 고정 / 같은 녹음 제목은 최신 시각→ID / 전체 동기화 메타정보와 현재 기기 파일 상태를 로컬 DB에서 조회.
- 세부: 기존 파일 필터 선택지·용량 부족 유지, UNKNOWN 및 잠정 개수 구분, 동일 조회 세대의 keyset 페이지와 조건 변경 시 초기화.
- 검토: 공통 입력·기대 순서·UTC 날짜 경계·동률·페이지 규칙, 링크와 기존 요구사항 ID 보존. README·요구사항·진행 기록을 함께 반영.
- 미실행: 실제 Dart/Java 정렬 시제품·DB 조회·기기 파일 검사·앱 UI·V/X 테스트. 문서 계약 완료와 기능 검증을 구분한다.
- 다음 작업: P00-06 입력과 누락 API 계약(D05~D08).
- 커밋: 이 파일의 GitHub History에서 확인.

### 1.4 — 2026-09-16

P00-06 입력과 누락 API 계약 완료.

- 결정: [D05](decisions/D05-input-length.md) 코드 포인트(앞선 추천 유지), [D06](decisions/D06-condition-tags.md) 고정 컨디션 0~1개·커스텀 태그 복수, [D07](decisions/D07-playlist-delete.md) 영구 삭제 안내·확인, [D08](decisions/D08-settings-storage-requests.md) 기기 강조색·반복 요청 허용.
- 새 사용자 제출은 별도 건수로 접수하며 동일 제출의 전송 재시도만 멱등 처리한다. 고유 요청 사용자 수는 별도 집계한다.
- [공통 수용 사례](contracts/P00-06-examples.md)와 요구사항·README를 연결했다. 원본 자료는 보존한다.
- 검토: 링크·ID 연속성, 기존 공통 revision/멱등 계약과 새 반복 제출 정책의 구분, 영구 삭제 범위, UI/API/DB 컨디션 규칙 일치.
- 실제 앱·서버·DB 테스트는 실행하지 않았다. V/X 통과 수는 증가시키지 않는다.
- 다음: P00-07 스냅샷과 백업 계약(D09~D11). 커밋은 이 파일의 GitHub History에서 확인.

### 1.5 — 2026-09-16

P00-07 스냅샷과 백업 계약 완료. 사용자 모든 추천 방법 승인 반영.

- [D09](decisions/D09-materialized-snapshots.md): MySQL 사본, READY 후 30분, 일관 cursor·생성/용량/청소·중단 재개.
- [D10](decisions/D10-offline-backup.md): 오프라인 부분 ZIP, 로컬 1·2·3/서버 a·b·c 사례, 포함/누락·cursor·작업 재개.
- [D11](decisions/D11-deletion-status.md): 상태 전용 확인증 30일, 준비 후 탈퇴로 응답 유실 대응, 일반 접근 차단 유지.
- [공통 사례](contracts/P00-07-examples.md)와 요구사항·README 연결 및 원본 보존 확인.
- 검증 범위: 문서 링크·요구사항 ID·선택안/계약 일치. 실제 DB/ZIP/인증/R2/운영 복구는 미실행. V/X 실행 수 불변.
- 다음 작업: P00-08 공통 검증 데이터 작성. P00-03 외부 데이터 이용 조건 확인 대기는 그대로 남는다.
- 커밋: 이 파일의 GitHub History 참조.

### 1.6 — 2026-09-16

P00-08 공통 검증 데이터 작성 완료. [fixtures](../fixtures/README.md)·[검증 결과](research/P00-08-validation.json). 169사례 중 31개 Python 참조 계산 대조, 138개 통합 시나리오 미실행. 정상 M4A 2개·손상 1개의 해시/디코딩 확인. S06 자모 순서 오류를 D02 코드순에 맞게 정정.

계획서의 앱·서버 실제 공통 데이터 소비 검증은 P01/P03에서 수행한다. V/X 제품 테스트 수는 불변. 다음은 P01 개발 환경·골격이며 P00-03 이용 조건 확인 대기는 유지한다.

### 1.7 — 2026-09-16

P01-01 저장소 구조 만들기 완료. 앱·서버·환경 폴더에 역할 README를 추가하고 루트 README를 연결했다. infra/.env.example은 실제 비밀번호 없이 이름만 정의했다.

- 검증: Git 제외 규칙에서 로컬 환경/서명 키/빌드·캐시 제외, 예시/lockfile/Wrapper 추적 가능 여부 확인. 원격 파일·기존 파일 보존 확인.
- 범위: 디렉터리 구성과 설정 예시. Flutter/Spring 프로젝트·컨테이너·빌드·DB 연결은 미실행.
- 기존 docs/reference 및 공통 fixtures는 변경하지 않았다.
- 다음: P01-02 Flutter 프로젝트 생성. 커밋은 이 파일의 GitHub History 참조.


### 1.8 — 2026-09-16

P01-02 Flutter 프로젝트 생성 완료.

- 실행 환경: Windows 11, Flutter 3.47.4 stable, Dart 3.13.3, Android SDK 36 계열, 실제 기기 SM A546S, Android 16(API 36).
- 사용자 확인: `flutter pub get`, `flutter analyze`, `flutter test`, Chrome 실행 및 USB 연결 실제 기기 dev debug 실행 성공.
- 앱 식별자: 운영 `com.ksh321.songrecord`, 개발 `com.ksh321.songrecord.dev`, 검증 `com.ksh321.songrecord.staging`.
- 환경: Android flavor `dev/staging/prod`와 Dart define `APP_ENV`, `API_BASE_URL` 계약을 추가했다.
- 골격: 초기 라우트 `/`, 앱 진입점·설정·라우팅 분리, 기본 샘플 카운터 제거, 분석 엄격 옵션과 새 위젯 테스트 반영.
- 도구 기록: AGP 9.1.0, Kotlin 2.4.0, Android Gradle Wrapper 9.3.1, NDK 28.2.13676358, JVM target 17, `pubspec.lock` 추적.
- 해결 기록: NDK 누락을 SDK Manager 설치로 해결하고, AGP 9 flavor별 리소스 값 사용을 위해 `buildFeatures.resValues = true`를 적용했다.
- 범위: Riverpod·Drift·go_router·Dio는 각 기능 구현 단계에서 추가하고 해결 버전을 lockfile로 고정한다. 서버·DB 연결은 P01-03 이후다.
- 다음 작업: P01-03 Spring Boot 프로젝트 생성.


### 1.9 — 2026-09-16

P01-02 실제 Android 기기 실행 증거를 보완했다.

- 기기: Samsung SM A546S, Android 16(API 36), USB 디버깅.
- 실행: `flutter run -d <device-id> --flavor dev --dart-define=APP_ENV=dev`.
- 결과: `assembleDevDebug` 빌드·설치·앱 실행 성공.
- 선행 오류와 조치: NDK 28.2.13676358 누락은 SDK Manager에서 설치했고, AGP 9의 flavor 리소스 기능 비활성 오류는 `buildFeatures.resValues = true`로 수정했다.
- 판정: P01-02 완료 조건인 새 환경 의존성 설치 후 빈 앱 실행을 실제 Android 기기에서 확인했다.


### 2.0 — 2026-09-17

P01-03 Spring Boot 프로젝트 생성 및 기동 전 구성을 반영했다.

- 사용자 커밋에서 Spring Boot 4.1.1, Java Toolchain 21, Gradle Wrapper 9.7.1과 Web MVC·Validation·Security·JPA·Actuator·MySQL·Flyway 의존성을 확인했다.
- 사용자 Windows 환경에서 Eclipse Temurin 21.0.12.1의 java·javac 및 Gradle Launcher/Daemon JVM 21을 확인했다.
- P01-04의 MySQL 구성 전에도 서버 골격을 검증하도록 기본 bootstrap 프로필을 추가했다. 이 프로필은 DataSource·Hibernate JPA·Flyway 자동설정을 제외하며 운영용이 아니다.
- 테스트는 bootstrap 프로필로 고정했고 Gradle 의존성 잠금을 활성화했다.
- 사용자 환경에서 gradle.lockfile 생성, clean test 성공을 보고받았고 bootRun의 bootstrap 적용·Tomcat 8080·Started ApiApplication 로그를 확인했다. P01-03은 완료다.


### 2.1 — 2026-09-17

P01-03 Spring Boot 프로젝트 생성 완료.

- 검증 환경: Windows 11, Eclipse Temurin 21.0.12.1, Spring Boot 4.1.1, Gradle Wrapper 9.7.1.
- `dependencies --write-locks`: 사용자 환경에서 실행 및 `gradle.lockfile` 생성 확인 보고. 기록 시점 원격 저장소에는 아직 파일이 없어 후속 Push가 필요하다.
- `clean test`: `BUILD SUCCESSFUL` 사용자 확인.
- `bootRun`: 기본 `bootstrap` 프로필 적용, Tomcat 11.0.24가 8080 포트에서 시작, `Started ApiApplication in 1.759 seconds` 로그 확인.
- `bootRun`의 80% EXECUTING 표시는 서버가 종료될 때까지 작업이 계속 실행되는 정상 상태다.
- Spring Security의 생성 비밀번호 경고는 개발용 기본 자동설정이며 비밀번호 값은 문서에 기록하지 않는다.
- 완료 범위는 DB 없는 서버 골격이다. 실제 MySQL 연결과 Flyway 마이그레이션은 P01-04에서 검증한다.


### 2.2 — 2026-09-17

P01-04 MySQL 개발 DB 구성을 반영하고 로컬 검증 대기로 전환했다.

- Docker Desktop과 WSL 2는 사용자 환경에서 실행 가능한 상태로 확인했다.
- 계획 기준 MySQL 8.4.12 공식 이미지는 조회되지 않아, 같은 8.4 LTS 계열의 8.4.11을 `sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a`로 고정했다.
- Compose에 로컬 전용 포트, utf8mb4, UTC, named volume, healthcheck를 설정했다.
- Spring `dev` 프로필은 DB 비밀번호를 런타임 환경변수로만 받고 Hibernate 자동 스키마 변경을 막는다.
- Flyway는 P01-05에서 초기 마이그레이션을 추가할 때까지 비활성화했다.
- 남은 완료 조건: MySQL `healthy`, Spring Boot dev 프로필 연결 성공, MySQL 재시작 후 확인 데이터 유지.


### 2.3 — 2026-09-17

P01-04 MySQL 개발 DB 준비 완료.

- Windows 11·Docker Desktop에서 digest가 고정된 MySQL 8.4.11 컨테이너의 `healthy` 상태를 확인했다.
- Spring Boot `dev` 프로필에서 Hikari 연결 풀 시작과 `Started ApiApplication` 로그를 확인했다.
- 확인용 테이블에 `id = 1`을 저장한 뒤 MySQL 컨테이너를 재시작하고 동일 데이터를 조회해 named volume 영속성을 확인했다.
- 검증 후 확인용 테이블을 제거했다.
- 최초 Spring 연결의 MySQL 1045 오류는 수동 입력한 `DB_PASSWORD` 불일치가 원인이었다. 컨테이너의 `MYSQL_PASSWORD`와 동일하게 맞춰 해결했으며 비밀번호 값은 기록하지 않았다.
- Hibernate Dialect 오류는 인증 실패로 메타데이터를 읽지 못해 발생한 2차 오류였다.
- P01-04 완료 범위는 개발 DB 실행·서버 연결·데이터 유지다. Flyway 초기 스키마와 마이그레이션 검증은 P01-05에서 수행한다.


### 2.4 — 2026-09-17

P01-05 스키마 버전 관리 연결을 구현하고 로컬 검증 대기로 전환했다.

- `V1__baseline.sql`을 추가해 Flyway가 스키마 변경의 단일 소유자가 되도록 했다.
- V1은 `app_schema_metadata`를 생성하고 스키마 계약 버전 1을 기록한다. 전체 도메인 테이블은 각 기능 구현 단계의 후속 마이그레이션으로 추가한다.
- dev 프로필에서 Flyway 실행·기동 시 체크섬 검증을 켰고, `clean`과 자동 baseline은 막았다.
- Hibernate는 `ddl-auto=validate`로 설정해 임의 테이블 생성·수정 없이 향후 엔티티 매핑만 검증한다.
- 남은 완료 조건: 같은 MySQL DB에 첫 기동하여 V1 적용, 종료 후 재기동하여 기존 이력 검증과 서버 시작 확인.


### 2.5 — 2026-09-17

P01-05 스키마 버전 관리 연결 완료.

- 사용자 Windows 11 환경에서 MySQL 컨테이너가 실행된 상태로 Spring Boot `dev` 프로필을 기동했다.
- 첫 기동에서 Flyway V1 마이그레이션 적용과 서버 시작을 확인했다.
- 서버를 종료한 뒤 같은 DB로 다시 기동해 기존 마이그레이션 이력 검증과 `Started ApiApplication`을 확인했다.
- 빈 DB 첫 기동과 기존 DB 재기동이 모두 성공해 P01-05 완료 조건을 충족했다.
- 실행 중 생성한 `bootrun-error.log`는 임시 진단 파일이므로 Git 추적에서 제외한다. `gradle.lockfile`은 해결된 의존성 고정을 위해 추적한다.


### 2.6 — 2026-09-17

P01-06 헬스 조회 연결을 구현하고 실제 기기 검증 대기로 전환했다.

- Flutter가 `GET /actuator/health`를 호출해 상태와 원문 JSON을 표시한다.
- 연결 중·성공·실패 상태와 실패 후 재시도 동작을 추가했다.
- 앱 설정의 `API_BASE_URL`만 사용하며 MySQL 접속 정보는 앱에 넣지 않는다.
- Spring Security는 health 경로만 인증 없이 허용하고 나머지 경로는 현재 단계에서 거부한다.
- Android HTTP 허용은 debug manifest에만 적용했다.
- 주소 계약: 에뮬레이터 `10.0.2.2`, 실제 기기 USB `adb reverse` + `127.0.0.1`, 같은 Wi-Fi에서는 PC IPv4.
- 위젯 성공·실패 상태 테스트를 추가했다.
- 남은 완료 조건: 사용자 SM A546S에서 Spring Boot health 응답 `UP` 표시 확인.
