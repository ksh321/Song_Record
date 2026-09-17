# Spring Boot API 서버

P01-03에서 Java 21·Spring Boot 서버 골격을 생성했고, P01-04에서 MySQL 개발 연결을 확인했다. P01-05에서는 Flyway 마이그레이션과 스키마 검증을 연결했다.

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

P01-04 검증 당시 Hibernate의 `ddl-auto`는 `none`, Flyway는 비활성 상태였다. P01-05부터는 Flyway만 스키마를 변경하고 Hibernate는 `validate`만 수행한다. MySQL 실행·연결·영속성 검증 명령은 [infra README](../../infra/README.md)를 따른다.


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


## P01-05 Flyway 스키마 버전 관리

`dev` 프로필에서 Flyway를 활성화했다. 최초 마이그레이션 `V1__baseline.sql`은 `app_schema_metadata`를 만들고 스키마 계약 버전 `1`을 기록한다. Flyway는 적용 이력과 체크섬을 `flyway_schema_history`에 저장한다.

- 스키마 변경은 `db/migration/V<번호>__<설명>.sql` 파일로만 추가한다.
- 이미 적용한 마이그레이션 파일은 수정하지 않는다. 변경이 필요하면 다음 번호 파일을 만든다.
- `spring.jpa.hibernate.ddl-auto=validate`: Hibernate는 매핑을 검사할 뿐 테이블을 생성·수정하지 않는다.
- `spring.flyway.validate-on-migrate=true`: 기동할 때 적용 이력과 파일 체크섬을 검사한다.
- `spring.flyway.clean-disabled=true`: 애플리케이션에서 DB 전체 삭제 명령을 실행하지 못하게 막는다.
- `baseline-on-migrate=false`: Flyway가 관리하지 않던 기존 테이블을 임의로 기준선 처리하지 않는다.

### Windows 검증

MySQL 컨테이너가 `healthy`인 상태에서 `services/api` PowerShell에 DB 비밀번호를 주입하고 실행한다. 비밀번호는 저장소에 기록하지 않는다.

```powershell
.\gradlew.bat bootRun --args="--spring.profiles.active=dev"
```

첫 실행 성공 기준:

- Flyway가 스키마 기록 테이블을 만들고 버전 1을 적용한다.
- Hikari 연결 풀이 시작한다.
- `Started ApiApplication`이 출력된다.

`Ctrl+C`로 종료한 뒤 같은 명령을 다시 실행한다. 두 번째 실행에서 Flyway가 기존 버전 1을 검증하고 추가 적용 없이 서버가 시작되면 “빈 DB 기동”과 “기존 DB 재기동” 조건을 모두 만족한다.

적용 결과는 MySQL에서 다음처럼 확인한다.

```sql
SELECT installed_rank, version, description, success
FROM flyway_schema_history
ORDER BY installed_rank;

SELECT * FROM app_schema_metadata;
```

예상값은 성공한 버전 `1` 한 건과 `schema_contract = 1`이다. 2026-09-17 Windows 11 환경에서 첫 기동의 V1 적용과 같은 DB 재기동의 이력 검증·서버 시작을 모두 확인해 P01-05를 완료했다.


### P01-05 검증 결과

| 검증 | 결과 |
|---|---|
| 빈 DB 첫 기동 | Flyway V1 적용 후 서버 시작 성공 |
| 기존 DB 재기동 | 기존 마이그레이션 이력·체크섬 검증 후 서버 시작 성공 |
| Hibernate | `ddl-auto=validate`, 자동 스키마 변경 없음 |
| 상태 | P01-05 완료 |

실행 과정에서 생성한 `bootrun-error.log`는 진단용 임시 파일이므로 커밋하지 않는다. `gradle.lockfile`은 실제 해결된 의존성 버전을 고정하므로 저장소에서 추적한다.


## P01-06 개발 health 공개 범위

Flutter 개발 앱이 인증 정보 없이 상태를 확인할 수 있도록 `GET /actuator/health`만 공개했다. 그 밖의 요청은 현재 보안 설정에서 거부한다. health 응답의 상세 정보는 계속 숨기며, 기본 응답은 `{"status":"UP"}`이다.

실제 Android 앱은 MySQL에 직접 연결하지 않는다. 연결 순서는 `Flutter → Spring Boot /actuator/health → Spring Boot 상태 검사`다. 휴대폰 연결과 주소별 실행 방법은 [모바일 README](../../apps/mobile/README.md)를 따른다.
