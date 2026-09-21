# Song_Record
노래방 노래 검색, 녹음, 노래의 다양한 정보 기록 관리 앱

2026-09-21: P04-06 동기화·삭제·작업 대기열 스키마와 로컬 검증을 추가했다. 커밋·push 및 새 CI 확인은 대기 중이다. 실제 사용자 DB 적용과 API·작업 실행기 연결은 별도 단계다.
[P04-06 변경과 검증](docs/verification/P04-06-sync-deletion-jobs.md) · [P04-05 보관·용량](docs/verification/P04-05-retention-storage.md) · [비개발자를 위한 DB 작업 안내](docs/database-guide.md)

## 기준 파일

| 자료 | 파일명 | 버전 | SHA-256 | 구현할 때의 역할 |
|---|---|---|---|---|
| 설계서 | `노래기록앱_구현설계서_v1.11.docx` | v1.11 | `957786385b081e52cdca2f83250b712701bcb63a73df63df47c1983a5916fe36` | 기능·데이터·API·삭제·동기화·보관 정책 |
| HTML | `b-playlist-ui-v1.11.html` | v1.11 | `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555` | 화면 배치·버튼·화면 이동·상호작용 참고 |
| UI_REFERENCE | `UI_REFERENCE.md` | HTML v1.11 대응 | `b62babdba6a124277e57e57b56a605325cd961e4040c73cca8a9c03a96a53d17` | 공통 UI 구성과 조작 규칙 |
| 색상 JSON | `ui_reference_palette.json` | 스키마 v1·HTML v1.11 대응 | `88ad5972f79424629b87698760ca98894c4f65fc23d9448bcec1effc4d12d83b` | 색상·글자 크기·간격·컴포넌트 치수 |
| 코드 구현 참고 사항 | `코드 구현 참고 사항.txt` | 버전 표기 없음 | `9f6a8df4f0908e61ca8a3612b83f4f26610ccdb0cec5165a541a73cb72bf10bd` | 자료별 적용 범위와 구현 기준 |

## 대응 관계 확인

- 설계서와 HTML의 기준 버전은 모두 `v1.11`이다.
- `UI_REFERENCE`는 `b-playlist-ui-v1.11.html`을 기준으로 작성됐다.
- 색상 JSON의 `source.sha256`은 HTML의 실제 SHA-256과 일치한다.
- HTML 기준 SHA-256: `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555`
- 따라서 설계서 v1.11과 HTML·UI 규칙·팔레트의 대응 관계를 확인할 수 있다.

## 현재 구현 기준과 변경 계약

- [요구사항 목록](docs/requirements.md) · [진행 기록](docs/progress.md)
- [D01: A안 구현 기술 결정](docs/decisions/D01-implementation-stack.md) · [버전 기준·고정 대상](docs/contracts/toolchain-versions.md)
- [D02: 공통 정렬](docs/decisions/D02-sort-order.md) · [D03: 날짜·동률](docs/decisions/D03-date-boundaries.md) · [D04: 기기 파일 필터](docs/decisions/D04-device-file-filter.md)
- [P00-05 공통 입력·기대 결과·페이징 사례](docs/contracts/P00-05-examples.md)
- [D12: 일간·주간·월간 인기곡 채택](docs/decisions/D12-popular-periods.md)
- [P00-03 외부 데이터 조사 및 실제 호출 결과](docs/research/external-data.md)

2026-09-16 사용자 승인: 차트는 과거 연월 선택 대신 Manana의 TJ/KY 일간·주간·월간 인기곡으로 구현한다. 원본 설계서·구현계획서·HTML·UI_REFERENCE의 차트 관련 내용과 충돌하면 D12를 우선 적용한다. 원본 파일과 해시는 보존한다. API 호출 성공과 이용 허용·집계 정확성·앱 통합 검증은 구분한다.

P00-05 완료: 추천 조합을 D02~D04로 확정했다. 정렬·날짜·기기 파일 필터의 세부 구현 계약은 해당 결정서를 따른다. 원본 자료는 보존하며 실제 앱·서버 검증 결과는 후속 구현 단계에서 기록한다.

## P00-06 입력과 누락 API 계약 — 완료

- [D05 입력 길이](docs/decisions/D05-input-length.md) · [D06 컨디션과 태그](docs/decisions/D06-condition-tags.md)
- [D07 목록 영구 삭제](docs/decisions/D07-playlist-delete.md) · [D08 설정과 반복 보관 요청](docs/decisions/D08-settings-storage-requests.md)
- [P00-06 공통 수용 사례](docs/contracts/P00-06-examples.md)

컨디션은 매우 좋음·좋음·보통·안 좋음 중 0~1개, 태그는 사용자 커스텀·복수 선택이다. 목록은 영구 삭제·복원 불가를 먼저 안내하고 확인 후 삭제하며 곡·녹음은 유지한다. 강조색은 기기별 저장한다. 보관 요청은 새 제출마다 반복 접수하며 같은 요청의 통신 재시도는 중복 저장하지 않는다. 충돌하는 원본의 컨디션 관리·요청 설명은 D06/D08을 우선 적용한다.

## P00-07 스냅샷과 백업 계약 — 완료

- [D09 MySQL 임시 스냅샷](docs/decisions/D09-materialized-snapshots.md)
- [D10 오프라인 부분 백업](docs/decisions/D10-offline-backup.md)
- [D11 탈퇴 상태 전용 확인증](docs/decisions/D11-deletion-status.md)
- [P00-07 공통 수용 사례](docs/contracts/P00-07-examples.md)

사용자 승인으로 모두 추천 A안 확정. 스냅샷은 준비 완료 후 30분, 오프라인 ZIP은 현재 기기 기준 부분 백업, 탈퇴 확인증은 접수 후 30일이다. 만료·중단 재개·포함/누락·인증·완료 표시의 세부 기준은 결정서를 따른다. 실제 앱·서버 기능 테스트는 후속 구현 단계에서 수행한다.

## P00-08 공통 검증 데이터 — 작성 완료

[공통 데이터·사용 방법](fixtures/README.md) · [자체 검증 결과](docs/research/P00-08-validation.json)

169사례(참조 대조 31, 후속 통합 명세 138), 정상 합성 M4A 2개·잘림 파일 1개. 제품 앱/서버 테스트는 별도다.

## 저장소 구조 — P01-01 완료

| 경로 | 역할 |
|---|---|
| [apps/mobile](apps/mobile/README.md) | Flutter Android 앱, P01-02 실행 골격 완료 |
| [services/api](services/api/README.md) | Spring Boot 4.1.1 서버 골격, P01-03 테스트·기동 완료 |
| [infra](infra/README.md) | MySQL 8.4 LTS Compose·개발 DB 실행 절차 |
| [docs](docs/requirements.md) | 설계·결정·요구사항·진행 기록 |
| [fixtures](fixtures/README.md) | 앱·서버 공통 검증 자료 |
| [tools](tools/validate_fixtures.py) | 검증 도구 |

로컬 비밀 설정·빌드 결과는 루트 `.gitignore`로 제외하고 앱 lockfile·Gradle Wrapper는 추적한다. Flutter 빈 앱은 dev 환경에서 실행 확인했다. Spring Boot 서버 골격은 테스트와 기동을 확인했다. MySQL Compose와 Spring `dev` 프로필은 P01-04에서 구성하고 로컬 연결·영속성을 확인했다. P01-05 Flyway 설정과 최초 마이그레이션을 반영하고 첫 기동·재기동까지 확인했다.


## P01-02 Flutter 프로젝트 — 완료

고유 Android 앱 ID, dev/staging/prod 환경, 초기 경로 `/`, 분석 규칙과 기본 테스트를 설정했다. 실행 명령과 환경 계약은 [모바일 README](apps/mobile/README.md)를 따른다.


## P01-03 Spring Boot 프로젝트 — 완료

Java 21, Spring Boot 4.1.1, Gradle Wrapper 9.7.1과 필수 서버 의존성을 반영했다. MySQL 설치 전 골격 검증용 `bootstrap` 프로필에서 `clean test`와 Tomcat 8080 서버 기동을 확인했다. 실행 방법과 검증 범위는 [서버 README](services/api/README.md)를 따른다.


## P01-04 MySQL 개발 DB — 완료

MySQL 8.4.11 이미지를 SHA-256 digest로 고정하고, 로컬 전용 포트·utf8mb4·UTC·named volume·healthcheck를 설정했다. Spring Boot `dev` 프로필의 Hikari 연결과 MySQL 재시작 후 데이터 유지까지 Windows 11에서 확인했다. 자동 스키마 변경과 Flyway 실행은 막아 두었으며 Flyway 초기 마이그레이션은 P01-05에서 진행한다.


## P01-05 스키마 버전 관리 — 완료

Flyway 최초 마이그레이션과 기동 시 체크섬 검증을 연결했다. Hibernate는 `validate`만 수행하고, DB 변경은 버전이 붙은 SQL 마이그레이션으로만 진행한다. 자세한 실행·확인 방법은 [서버 README](services/api/README.md)를 따른다. Windows 11 환경에서 같은 DB의 첫 실행과 재실행이 모두 성공해 완료했다.


## P01-06 Flutter 서버 health 연결 — 완료

Flutter 개발 화면에서 Spring Boot `/actuator/health`를 호출해 상태와 JSON 응답을 표시하도록 연결했다. Android 로컬 HTTP 허용은 debug 빌드로 제한했으며, 실제 기기는 USB `adb reverse`, 에뮬레이터는 `10.0.2.2`를 사용한다. SM A546S에서 USB `adb reverse`를 통한 실제 Spring Boot 호출과 `UP` 표시를 확인했다.


## P01-07 기본 오류와 로그 — 완료

Spring Boot에 요청 ID, 공통 오류 JSON, 환경별 로그 수준과 민감정보 마스킹 테스트를 추가했다. Flutter는 공통 오류를 파싱해 오류 코드와 요청 ID를 표시한다. Windows 11에서 서버 `clean test`, Flutter `analyze/test`, dev 오류 응답과 동일 요청 ID의 서버 로그를 확인했다. Spring Security 자동 생성 비밀번호도 로그에 남지 않도록 제거해 완료했다.


## P01-08 최소 자동 검증 — 완료

GitHub Actions가 새 Ubuntu 환경에서 Flutter 분석·테스트, Spring Boot 빌드·테스트, MySQL Compose 기동과 실제 쿼리를 각각 실행한다. 외부 Action, Flutter, Java, Gradle, MySQL 버전은 저장소 계약에 맞춰 고정했다. GitHub Actions 실행 #2에서 세 작업이 모두 성공해 P01-08을 완료했다.

자세한 검사 항목과 새 체크아웃 순서는 [P01-08 검증 문서](docs/verification/P01-08-ci.md)를 따른다.

## P02-01~03 Android 녹음 시제품 — 구현 완료·실기 확인 대기

Flutter `RecorderGateway`와 Android microphone foreground service를 연결했다. 사용자가 누른 경우에만 권한을 요청해 AAC 96kbps·48kHz·모노 M4A를 앱 내부 영구 경로에 만들며, 화면 재생성 시 서비스 상태를 다시 구독한다. 종료 후 실제 오디오 형식을 표시하고 앱에서 재생할 수 있다.

자동 분석·테스트·dev APK 빌드는 GitHub Actions에서 확인하고, 실제 Android 기기에서 권한 거절·재허용과 녹음·재생을 확인한 뒤 P02-01~03을 완료 처리한다. 자세한 순서는 [P02-01~03 검증 문서](docs/verification/P02-01-03-recorder.md)를 따른다.
