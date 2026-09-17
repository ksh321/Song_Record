# Spring Boot API 서버

P01-03에서 Java 21·Spring Boot 서버 골격을 생성했다. 실제 MySQL 개발 환경은 P01-04에서 연결한다.

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
