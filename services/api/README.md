# Spring Boot API 서버

P01-03에서 Java 21·Spring Boot 서버 골격을 생성했고, P01-04에서 MySQL 개발 연결 프로필을 추가했다.

## 현재 고정한 도구

| 대상 | 실제 값 |
|---|---|
| Java Toolchain | 21 |
| 로컬 JDK 검증 | Eclipse Temurin 21.0.12.1+1 LTS |
| Spring Boot | 4.1.1 |
| Gradle Wrapper | 9.7.1 |
| 패키지 | `com.ksh321.songrecord.api` |

Spring Boot 4.1.1은 Gradle 8.14 이상과 Gradle 9.x를 지원한다. Initializr가 생성한 Wrapper 9.7.1을 저장소 기준으로 사용한다.

## 포함한 의존성

- Spring Web MVC
- Validation
- Spring Security
- Spring Data JPA
- Actuator
- MySQL Connector/J
- Flyway와 Flyway MySQL 모듈

각 라이브러리의 개별 버전은 Spring Boot 4.1.1 BOM에 맡기며 임의로 덮어쓰지 않는다.

## bootstrap 프로필

기본 프로필은 `bootstrap`이다. P01-04 전에도 웹 서버 골격과 Spring Context를 검사할 수 있도록 이 프로필에서 DataSource·Hibernate JPA·Flyway 자동설정만 제외한다.

- MySQL이 없어도 서버 골격과 테스트를 실행할 수 있다.
- DB CRUD나 마이그레이션 성공을 의미하지 않는다.
- 운영에서는 절대 사용하지 않는다.
- P01-04에서 실제 MySQL용 개발 프로필을 추가한다.

## Windows 검증 명령

`services/api`에서 실행한다.

```powershell
.\gradlew.bat --version
.\gradlew.bat dependencies --write-locks
.\gradlew.bat clean test
.\gradlew.bat bootRun
```

`bootRun` 로그에 `Started ApiApplication`이 나오면 서버 골격 기동 성공이다. 실행 중인 서버는 `Ctrl+C`로 종료한다. Spring Security의 임시 비밀번호 로그는 기본 보안 자동설정 때문에 나오는 것으로 빌드 오류가 아니다.

`dependencies --write-locks`가 만든 `gradle.lockfile`은 커밋한다. 빌드 결과와 Gradle 캐시는 커밋하지 않는다.

- 기술 기준: [D01](../../docs/decisions/D01-implementation-stack.md), [버전 목록](../../docs/contracts/toolchain-versions.md)
- API·정책 기준: [요구사항](../../docs/requirements.md), [결정 기록](../../docs/decisions/)
- 공통 데이터: [fixtures](../../fixtures/README.md)
- 비밀값은 런타임 환경 변수로 주입한다.


## P01-03 검증 결과

2026-09-17 Windows 11 환경에서 다음을 확인했다.

| 검증 | 결과 |
|---|---|
| Java·Gradle | Temurin 21.0.12.1, Gradle 9.7.1 |
| 의존성 잠금 생성 | `dependencies --write-locks` 성공, 로컬 `gradle.lockfile` 생성 |
| Context 테스트 | `clean test` → `BUILD SUCCESSFUL` |
| 서버 기동 | 기본 `bootstrap` 프로필 적용 |
| 내장 서버 | Tomcat 11.0.24, HTTP 8080 |
| 완료 로그 | `Started ApiApplication in 1.759 seconds` |

`bootRun`은 서버를 계속 띄우는 장기 실행 작업이므로 Gradle 표시가 80% EXECUTING에서 유지되는 것이 정상이다. 멈춘 것이 아니며 `Ctrl+C`로 서버를 종료하면 작업도 끝난다.

이 검증은 Spring Web 서버와 애플리케이션 Context가 정상 구성됐다는 뜻이다. `bootstrap` 프로필에서는 DB 관련 자동설정을 끈다. 실제 MySQL 연결과 재시작 후 데이터 유지 검증은 P01-04 절차로 수행하며, Flyway 마이그레이션은 P01-05에서 수행한다.


## P01-04 MySQL 개발 프로필

`dev` 프로필은 `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` 환경변수로 MySQL에 연결한다. 기본값은 로컬 호스트·3306·`song_record`이며 비밀번호에는 기본값이 없다.

Hibernate의 `ddl-auto`는 `none`으로 고정해 자동 스키마 변경을 막았다. Flyway는 P01-05 전까지 비활성화했다. MySQL 실행·연결·영속성 검증 명령은 [infra README](../../infra/README.md)를 따른다.


## P01-04 검증 결과

2026-09-17 Windows 11에서 MySQL 8.4.11 컨테이너가 `healthy`인 상태로 `dev` 프로필을 실행했다.

| 검증 | 결과 |
|---|---|
| 활성 프로필 | `dev` |
| 연결 풀 | `HikariPool-1 - Start completed` |
| 서버 | `Started ApiApplication` |
| 데이터 영속성 | MySQL 재시작 후 확인 행 `id = 1` 유지 |
| 정리 | 확인용 테이블 제거 |

최초 시도에서는 Spring의 `DB_PASSWORD`가 컨테이너의 `MYSQL_PASSWORD`와 달라 MySQL 1045 인증 오류가 발생했다. 두 값을 일치시켜 해결했다. 비밀번호 값 자체는 저장소와 로그에 기록하지 않는다.
