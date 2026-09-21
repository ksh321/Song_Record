# 구현 기술 버전 기준 및 고정 대상
- 문서 버전: 2.0
- 확인일: 2026-09-21
- 결정: [D01 A안](../decisions/D01-implementation-stack.md)
- 상태: 기술 기준 확정 / P01-02~P01-08 완료

## 초기 버전 기준
아래 값은 프로젝트 생성 시 사용할 기준이다. 빌드 성공을 증명하는 lockfile은 아니다.

| 대상 | 기준 | 근거 |
|---|---|---|
| Flutter | 3.47.4 stable (P01-02 실제 사용) | [공식 SDK 아카이브](https://docs.flutter.dev/install/archive) |
| Dart | Flutter 3.47.4에 동봉된 3.13.3 | 위 아카이브의 SDK 대응표. 별도 Dart로 교체하지 않음 |
| flutter_riverpod | 3.4.3 | [공식 패키지 버전](https://pub.dev/packages/flutter_riverpod/versions), 최소 Dart 3.12 |
| drift / drift_dev | 각각 2.35.0 | [drift](https://pub.dev/packages/drift/versions), [drift_dev](https://pub.dev/packages/drift_dev/versions), 최소 Dart 3.10 |
| go_router | 18.0.1 | [변경 기록](https://pub.dev/packages/go_router/changelog), 18 계열 최소 Flutter 3.44 / Dart 3.12 |
| dio | 5.11.1 | [버전 목록](https://pub.dev/packages/dio/versions), 최소 Dart 2.18 |
| 서버 Java | 21 LTS / 로컬 Eclipse Temurin 21.0.12.1+1 | Java Toolchain 21, 사용자 Windows 환경에서 java·javac·Gradle JVM 확인 |
| Spring Boot | 4.1.1 | [시스템 요구사항](https://docs.spring.io/spring-boot/system-requirements.html) |
| 서버 Gradle Wrapper | 9.7.1 (Initializr 실제 생성값) | [Spring Boot 4.1.1 시스템 요구사항](https://docs.spring.io/spring-boot/system-requirements.html)의 Gradle 9.x 지원 범위 |
| Spring Data JPA / Hibernate / MySQL JDBC / Flyway | Spring Boot 4.1.1 BOM 관리 버전 | [관리 의존성](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html). 임의 개별 버전 덮어쓰기 금지 |
| MySQL | 8.4.11, 8.4 LTS 계열 · `mysql:8.4.11@sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a` | 계획 기준 8.4.12 공식 Docker 이미지를 조회할 수 없어 실제 제공된 같은 LTS 계열 이미지를 digest로 고정 |
| SQLite 네이티브 패키지·코드 생성 보조 도구 | P04-08: sqlite3 3.5.2 / build_runner 2.16.1 / Drift·drift_dev 2.35.0 | pubspec.lock 고정. 로컬 시험 SQLite 3.51.1, 기본 번들·Android 런타임은 CI/실기 확인 대기 |
| Android AGP / Kotlin / Gradle / SDK | AGP 9.1.0 / Kotlin 2.4.0 / Gradle Wrapper 9.3.1 / Android SDK 36 계열 | Flutter 3.47.4 생성 템플릿과 실제 프로젝트 파일 기준 |
| R2 연동 SDK | 서버 구현 시 선택·고정 | 비공개 저장소 정책 유지 |
| 녹음 플러그인 | P02 실기 결과 후 결정 | D01 완료와 별도 |

## 호환 조건 검토
- Flutter에 동봉된 Dart 3.13.3는 위 패키지의 명시된 최소 Dart 버전 이상이다. Flutter 3.47.4는 go_router 18의 최소 Flutter 조건 이상이다.
- Boot 4.1.1의 공식 Java 범위는 17~26이며 Java 21은 그 범위 안이다. 실제 Wrapper 9.7.1은 공식 지원되는 Gradle 9.x 범위에 해당한다.
- 이는 공개 요구 조건의 정적 대조다. 전이 의존성 충돌, Android 플러그인 조합, DB 연결은 실제 프로젝트에서 확인해야 한다.

## P01 고정 대상 체크리스트
- [ ] Flutter SDK 정확한 버전·revision·다운로드 체크섬을 개발 환경과 CI에 동일 적용
- [x] P01-02 기본 앱 pubspec.yaml과 실제 해결된 pubspec.lock 커밋 (기능 의존성은 담당 단계에서 추가)
- [ ] Drift 보조 패키지·코드 생성 도구와 SQLite 네이티브 런타임 버전 기록
- [x] 앱 Android AGP 9.1.0·Kotlin 2.4.0·Gradle Wrapper 9.3.1 기록 및 실제 Android 기기 dev debug 빌드·실행 확인
- [ ] 서버 Java 로컬 배포판·패치는 Temurin 21.0.12.1+1로 확인. CI/컨테이너 이미지 digest는 미정
- [ ] 서버 Boot 플러그인/BOM 4.1.1과 Wrapper 9.7.1 파일 커밋. Wrapper 배포 체크섬은 미기록
- [ ] 서버 의존성 잠금은 활성화했고 로컬 gradle.lockfile 생성을 확인. 원격 파일 추적·검증 메타데이터와 실제 JPA/JDBC/Flyway 버전 기록은 남음
- [x] Flyway MySQL 지원 모듈과 V1 baseline 반영, 첫 기동 적용과 기존 DB 재기동 검증 완료
- [x] MySQL 8.4.11 공식 이미지를 `sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a`로 고정 (8.4.12는 조회 시 미제공, latest 금지)
- [ ] 생성한 lock/Wrapper로 깨끗한 환경에서 재빌드 후 명령·결과·커밋 기록

## 이후 변경
버전 변경은 변경 이유와 빌드 결과를 함께 기록한다. 보안 패치도 검증 후 갱신하며 문서 값과 실제 lockfile이 다르면 차이를 해결한다. 미설치 도구의 해시나 아직 해결하지 않은 의존성 버전을 임의로 작성하지 않는다.


## P01-02 실제 환경 기록

- Flutter 3.47.4 stable / Dart 3.13.3를 사용했다. 초기 기준 3.47.2/3.13.2에서 stable 패치 버전으로 갱신했다.
- Android 앱은 JVM target 17과 NDK 28.2.13676358을 사용한다. 서버 Java 21 결정과는 별개다.
- `flutter pub get`, `flutter analyze`, `flutter test`, Chrome 및 실제 기기 Samsung SM A546S(Android 16/API 36) dev debug 실행을 사용자 환경에서 확인했다.
- Flutter SDK revision·배포 체크섬과 CI 고정은 P01-08에서 기록한다.

- AGP 9에서 flavor별 `resValue`를 사용하기 위해 `android.buildFeatures.resValues = true`를 명시했다.


## P01-03 실제 생성 환경 기록

- Spring Initializr 생성 결과: Spring Boot 4.1.1, Gradle Groovy, Java Toolchain 21, Jar.
- 패키지: `com.ksh321.songrecord.api`.
- Gradle Wrapper 9.7.1과 Launcher/Daemon JVM Temurin 21.0.12.1을 사용자 Windows 환경에서 확인했다.
- Web MVC·Validation·Security·Data JPA·Actuator·MySQL·Flyway 의존성을 추가했고 개별 버전은 Boot BOM에 맡겼다.
- P01-04 전 서버 골격 검증을 위해 기본 `bootstrap` 프로필에서 DataSource·Hibernate JPA·Flyway 자동설정을 제외했다.
- Gradle 의존성 잠금을 활성화했고 사용자 환경에서 `gradle.lockfile` 생성과 `clean test` 성공을 확인했다. `bootRun`은 bootstrap 프로필, Tomcat 11.0.24/8080, `Started ApiApplication in 1.759 seconds`로 성공했다.


### P01-03 실행 검증

- 검증일: 2026-09-17.
- `clean test`: 성공.
- `bootRun`: Java 21.0.12.1, 기본 bootstrap 프로필, Tomcat 11.0.24, HTTP 8080, 애플리케이션 시작 성공.
- Gradle의 80% EXECUTING 표시는 서버 프로세스를 계속 유지하는 `bootRun` 특성에 따른 정상 상태다.
- 생성된 Spring Security 개발 비밀번호는 저장하지 않았으며 실제 인증 구성은 후속 단계에서 교체한다.
- DB 자동설정을 제외한 골격 검증이므로 MySQL 8.4와 Flyway 검증은 P01-04에서 수행한다.


## P01-04 MySQL 이미지 결정

- 계획 기준 8.4.12 태그는 공식 Docker 이미지에서 조회되지 않아 사용할 수 없었다.
- 같은 8.4 LTS 계열의 8.4.11을 조회하고 사용자 환경에서 확인한 repo digest를 Compose에 고정했다.
- 태그만 쓰지 않고 digest까지 지정하므로 같은 설정에서 다른 이미지가 내려오는 일을 막는다.
- Compose·Spring `dev` 프로필에서 컨테이너 `healthy`, Hikari 연결, 서버 기동, 재시작 후 데이터 유지를 Windows 11에서 확인했다.
- Flyway 실행과 초기 스키마는 P01-05에서 다룬다.


## P01-04 실제 검증 기록

- 환경: Windows 11, Docker Desktop, MySQL 8.4.11, Spring Boot 4.1.1, Java 21.
- 컨테이너 상태: `healthy`.
- 서버 연결: `dev` 프로필, Hikari 연결 풀 시작, `Started ApiApplication` 확인.
- 영속성: 확인용 테이블에 `id = 1`을 저장하고 MySQL 재시작 후 동일 행 조회, 이후 테이블 제거.
- 해결 기록: 최초 Spring 실행의 MySQL 1045 오류는 `DB_PASSWORD`와 컨테이너 `MYSQL_PASSWORD` 불일치가 원인이었으며 동일 값으로 맞춰 해결.


## P01-05 Flyway 스키마 관리 기준

- 마이그레이션 위치: `services/api/src/main/resources/db/migration`.
- 최초 파일: `V1__baseline.sql`.
- dev 프로필은 기동할 때 Flyway 이력·체크섬을 검증한다.
- Hibernate DDL 모드는 `validate`이며 스키마를 자동 생성·변경하지 않는다.
- Flyway `clean`과 자동 baseline은 비활성화했다.
- 적용된 파일은 수정하지 않고, 후속 변경은 증가한 버전 번호의 새 SQL 파일로 작성한다.
- 검증 완료: 빈 DB 첫 실행에서 V1 적용, 같은 DB 재실행에서 이력·체크섬 검증과 서버 기동 성공.


## P01-08 CI 실행 기준

| 대상 | 고정 기준 |
|---|---|
| actions/checkout | `11d5960a326750d5838078e36cf38b85af677262` (v4 참조 확인값) |
| actions/setup-java | `cf277c60eb25467037889841efdb72551f06f6c3` (v4 참조 확인값) |
| subosito/flutter-action | `1a449444c387b1966244ae4d4f8c696479add0b2` (v2 참조 확인값) |
| GitHub runner | `ubuntu-latest` |
| 워크플로 권한 | `contents: read` |

CI도 로컬과 같은 Flutter 3.47.4, Java 21, Gradle Wrapper 9.7.1, digest 고정 MySQL 8.4.11을 사용한다. Action 태그가 나중에 이동해도 동일 코드를 실행하도록 전체 커밋 SHA를 기록한다.


## P01-08 CI 검증 결과

- 검증일: 2026-09-17.
- 커밋: `8168aba2da7e39e7d08eee71fb7155ed6f9359fc`.
- GitHub Actions 실행: [CI #2](https://github.com/ksh321/Song_Record/actions/runs/35195006942).
- 결과: Flutter analyze/test, Spring Boot clean build, MySQL Compose 및 SELECT 1 모두 성공.
- MySQL 초기화 구간에서는 임시 서버의 health 응답과 실제 사용자 DB 준비 시점이 다를 수 있어, 검증 쿼리를 최대 60초 동안 재시도한다.

## P04-08 로컬 저장 구성

- Drift / drift_dev 2.35.0, sqlite3 3.5.2, build_runner 2.16.1, path 1.9.1, path_provider 2.1.6, crypto 3.0.7을 앱 `pubspec.lock`에 기록했다.
- Drift 생성 코드와 `drift_schemas/account/drift_schema_v1.json`을 함께 관리한다. CI는 잠금 파일로 설치하고 코드 재생성·현재 스키마와 보존본의 일치를 검사한다.
- 저장소는 sqlite3 패키지의 기본 네이티브 바이너리 구성을 유지한다. 별도 sqlite3_flutter_libs나 운영용 시스템 SQLite override는 추가하지 않았다.
- 로컬 원본 경로의 도구 캐시 접근 제한과 기본 네이티브 바이너리 다운로드 실패로 분리된 시험 복사본을 사용했다. 이 복사본에만 공식 hook 설정 `source: system`, `name_windows: winsqlite3`를 적용했고 Windows 내장 SQLite 3.51.1에서 분석·테스트를 수행했다.
- 기본 번들 바이너리 및 Android 조합의 검증 완료를 뜻하지 않는다. P04-08 업로드 후 기본 설정의 CI, 후속 기기 검증으로 확인한다. [상세 환경·검증](../verification/P04-08-account-local-storage.md)
