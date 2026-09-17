# 구현 기술 버전 기준 및 고정 대상
- 문서 버전: 1.4
- 확인일: 2026-09-17
- 결정: [D01 A안](../decisions/D01-implementation-stack.md)
- 상태: 기술 기준 확정 / P01-02 완료 / P01-03 Spring Boot 골격·테스트·기동 완료

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
| MySQL | 8.4.12, 8.4 LTS 계열 | [공식 릴리스 노트](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/news-8-4-12.html), 2026-08-18 배포 |
| SQLite 네이티브 패키지·코드 생성 보조 도구 | Drift 구성 후 P01에서 해결된 버전 고정 | SQLite 런타임 버전도 기록 |
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
- [ ] Flyway MySQL 지원 모듈 포함 여부 확인, 실제 MySQL 연결·마이그레이션 검증
- [ ] MySQL 8.4.12 이미지 사용 가능 여부 확인 및 digest 고정 (latest 금지)
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
