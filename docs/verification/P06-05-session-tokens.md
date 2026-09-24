# P06-05 접근·갱신 토큰 및 세션

기준 main: 09493595771d9c24e579a65f5a6a9d0ee96de021.
인증 소스 기준 Java 21 컴파일 및 JUnit 108개 성공(기존90+신규18).
전체 Gradle/실제 MySQL/실기 연결은 별도 검증이다.

## 변경 파일

- services/api/src/main/java/com/ksh321/songrecord/api/auth/SessionService.java
- services/api/src/main/java/com/ksh321/songrecord/api/auth/SessionConfiguration.java
- services/api/src/main/resources/db/migration/V8__session_token_rotation.sql
- services/api/src/test/java/com/ksh321/songrecord/api/auth/SessionServiceTests.java
- services/api/src/test/java/com/ksh321/songrecord/api/auth/SessionConfigurationTests.java
- services/api/src/test/resources/session-schema.sql

## 정책과 연결 경계

서버가 생성하는 256비트 SecureRandom opaque Bearer 토큰이다. JWT가 아니며 별도 서명키가 필요 없다.
접근 sr_a_, 갱신 sr_r_ 접두사로 유형을 구분하고 각각 독립 난수를 발급한다.
DB에는 SHA-256 해시만 저장한다. 원문은 발급 응답에서만 반환하며 toString은 REDACTED다.
실제 HTTP 연결에서는 HTTPS, Cache-Control: no-store, 요청/응답 본문 로그 제외가 필요하다.

auth.session.access-ttl 기본 PT15M, auth.session.refresh-ttl 기본 P30D.
최소 접근 유효기간 1초, 갱신 기간은 접근 기간 이상·365일 이하. 잘못된 설정은 시작 실패.
모든 시각은 UTC이며 DATETIME(3)과 일치하도록 밀리초 단위다.
갱신 30일은 최초 세션 발급부터의 절대 만료다. 교체해도 연장하지 않는다.
갱신 직후 접근 만료는 세션 만료를 넘지 않는다. 기존 접근 토큰은 원래 만료까지 유효하지만
세션 폐기·기기 폐기·DELETING 상태는 접근 검증에서 즉시 거부한다.

issue(Registration)는 반드시 서버 공급자 증명 검증/사용자 등록 후 내부에서만 호출한다.
userId/deviceId만 받는 공개 발급 API로 노출하면 안 된다. Registration DTO 자체는 인증 증명이 아니다.
authenticate(accessToken, deviceId)는 토큰 해시·기기·세션·계정 상태와 두 만료시각을 조회한다.
HTTP 엔드포인트와 Spring Security 필터 연결은 P06-06 앱 연결 작업에서 함께 처리한다.
현재 기본 SecurityConfig를 완화하지 않았으며 앱 로그인 UI도 변경하지 않았다.

## 갱신과 재사용 탐지

V8은 auth_refresh_token(사용된 토큰 포함 전체 해시 이력)과 auth_access_token을 추가한다.
기존 auth_session.refresh_hash는 현재 토큰 해시로 유지한다.
기존 세션의 현재 해시는 마이그레이션 시 이력으로 복사한다.
기존 V1~V7은 변경하지 않는다. 세션 삭제 시 두 토큰 테이블은 FK cascade로 삭제한다.

갱신 시 사용자 -> 기기 -> 세션 순으로 잠금. DB 잠금 후 현재 시각/해시/사용 이력을 재검사한다.
사용한 토큰은 consumed_at을 기록하고 새 접근·갱신 토큰을 같은 트랜잭션에서 저장한다.
실패하면 소비 표시와 교체 모두 롤백된다.
사용한 갱신 토큰이 재등장하면 해당 세션의 revoked_at을 저장하여 커밋한 뒤
401 AUTH_REFRESH_REUSED를 반환한다. 오류를 트랜잭션 안에서 던져 폐기를 취소하지 않는다.
다른 세션은 유지한다. 임의/틀린 기기의 요청은 유효 세션을 폐기하지 않는다.

동일 갱신 토큰을 두 번 동시에 보내면 하나가 갱신하고 다음 요청이 재사용을 감지해 세션을 폐기한다.
따라서 후속 앱은 갱신 요청을 단일화해야 한다. 응답 유실 후 같은 토큰 재시도 역시 재로그인이 필요하다.
외부 트랜잭션 안에서 issue/refresh 호출을 거부하여 보안 폐기 커밋 경계를 유지한다.
만료/폐기/임의 토큰/기기 불일치는 401 AUTH_INVALID_SESSION. DB 장애는 인증 성공으로 우회하지 않는다.

이력은 활성 세션 동안 삭제하면 안 된다. 만료된 접근 행은 삭제 가능하고,
갱신 이력은 세션 만료/삭제 이후 정리 가능하다. 이번 단계에는 자동 정리 스케줄러가 없다.
서버 DB 조회형이므로 복수 인스턴스가 같은 DB를 쓰면 별도 메모리 세션 동기화가 필요 없다.

## 테스트와 한계

18개 신규 JUnit: 발급/해시 보관/만료 기본값, 회전/절대 만료 유지,
재사용 폐기 커밋과 모든 접근 차단, 다른 세션 유지, 기기 불일치,
토큰 유형 혼동/잘못된 입력, 정확한 접근·갱신 만료 경계,
DELETING·폐기 기기 차단, 소유권 확인, 회전 중 DB 오류 롤백,
동시 갱신, 외부 트랜잭션 거부, 잘못된 TTL 및 profile 구성.
H2 메모리 DB의 실제 JDBC 트랜잭션으로 테스트한다. 실제 MySQL 잠금/마이그레이션 실행을 대체하지 않는다.
직접 javac + JUnit ConsoleLauncher로 108 성공, 0 실패.
작성 환경의 Gradle 플러그인 해석 제약으로 전체 Gradle은 사용자 PC/CI에서 확인해야 한다.
Apply-P06-05.ps1은 clean test bootJar를 실행한다. 기본 bootstrap에서는 실제 DB 마이그레이션을 하지 않는다.
DB 사용 profile로 서버를 실행하면 Flyway가 V8을 적용한다.
휴대폰 로그인/OS 보안 저장소/실공급자 토큰은 이번 단계에서 검증하지 않았다.

## 참고

https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14.2
https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/support/TransactionTemplate.html

다음: P06-06 앱 로그인 연결(서버 로그인·갱신 API/보안 필터 포함).
