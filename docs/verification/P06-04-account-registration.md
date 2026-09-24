# P06-04 사용자와 기기 등록

기준: f00c9aff403c4803e90c54f8bca4171c1f5d8e9f + 사용자가 적용·검증한 P06-03 패치.
구현 완료, 인증 테스트 90개 및 사용자 전체 Gradle 빌드 성공.
푸시 커밋: 09493595771d9c24e579a65f5a6a9d0ee96de021. 실제 MySQL 검증은 별도다.

## 코드 위치

- services/api/src/main/java/com/ksh321/songrecord/api/auth/AccountRegistrationService.java
- services/api/src/main/java/com/ksh321/songrecord/api/auth/AccountRegistrationConfiguration.java
- services/api/src/test/java/com/ksh321/songrecord/api/auth/AccountRegistrationTests.java
- services/api/src/test/java/com/ksh321/songrecord/api/auth/AccountRegistrationConfigurationTests.java
- services/api/src/test/resources/registration-schema.sql

## 동작

Google/Kakao 검증기가 반환한 VerifiedProviderIdentity만 내부 서비스에 전달한다.
클라이언트가 보낸 provider_user_id를 직접 이 서비스로 전달해서는 안 된다.
HTTP 엔드포인트는 추가하지 않았다. 공급자 네트워크 검증은 DB 트랜잭션 시작 전에 수행해야 한다.

첫 로그인은 app_user, auth_identity, user_sync_state, user_entitlement, storage_usage,
device를 하나의 트랜잭션에서 생성한다. 어떤 저장 단계든 실패하면 전부 롤백된다.
무료 기본값: FREE, 고정 10개, 1,000,000,000 bytes, 사용/예약 0, change_seq 0.
권한·용량은 클라이언트 입력을 받지 않는다. 기존 테이블 기본 revision을 사용한다.

동시 첫 로그인은 auth_identity(provider,provider_user_id) 고유 제약이 승자를 결정한다.
중복키나 DB 잠금 충돌 시 실패 트랜잭션 전체를 롤백한 뒤 새 트랜잭션에서 다시 조회한다.
최대 3회, READ_COMMITTED, 트랜잭션 제한 10초. 반복 충돌은 retryable 503 AUTH_REGISTRATION_BUSY.
예외를 같은 트랜잭션 안에서 삼키지 않는다. 외부 트랜잭션 안에서 호출하면 거부한다.
세션 발급 등 후속 작업은 이 등록 트랜잭션 완료 이후 수행해야 한다.

기존 사용자 로그인은 app_user 행을 잠그고 ACTIVE 상태를 검사한다.
DELETING은 ACCOUNT_UNAVAILABLE로 거부하며 새 계정으로 취급하지 않는다.
기존 권한/사용량/동기화 값을 초기화하지 않는다. 이메일로 계정을 찾거나 병합하지 않는다.

existingDeviceId=null이면 서버에서 새 UUID로 기기를 만든다.
기존 ID를 지정하면 같은 계정 소유이며 revoked_at이 null인 기기만 갱신한다.
다른 계정/없는/폐기된 기기는 DEVICE_UNAVAILABLE, 폐기된 행을 재활성화하지 않는다.
기기 ID는 인증 증명이 아니다. 동일 계정에서만 재사용하고 계정 전환 시 null로 새 등록한다.
응답을 잃어 null로 다시 요청하면 기기가 하나 더 생길 수 있으나 사용자는 중복 생성되지 않는다.
last_seen_at/updated_at은 서버 UTC 시각을 사용한다.

## 자동 테스트

H2 2.4.240을 testRuntimeOnly로 추가하고 lockfile에 testRuntimeClasspath 한 줄 추가했다.
배포 JAR에는 H2를 포함하지 않는다. 기존 MySQL 마이그레이션은 수정하지 않았다.
테스트마다 분리된 메모리 DB를 만들고 종료한다. 실제 JDBC와 Spring 트랜잭션 관리자를 실행한다.
DDL fixture는 V2/V5/V6의 관련 테이블에서 MySQL 문자집합/엔진 선언만 제거했다.
MySQL과 H2의 잠금/문자열 비교 차이가 있으므로 실제 MySQL 통합 검증을 대체하지 않는다.

14개 신규 테스트:
- 최초 데이터 전체 생성과 무료 기본값
- 재로그인 시 기기 재사용, 권한/사용량 보존
- 새 기기 등록과 기존 사용자 재사용
- 공급자가 다르면 같은 회원번호도 다른 계정
- 타인 기기 지정 거부 및 신규 계정 데이터 롤백
- 폐기 기기 재활성화 금지
- 탈퇴 진행 계정 거부
- 마지막 INSERT 강제 실패 시 전체 롤백
- 잘못된 이름/식별값 거부
- 외부 트랜잭션에서 호출 거부
- 8개 동시 로그인에서 사용자/연결/권한/사용량/동기화 각각 1행, 기기 8행
- bootstrap 비활성 및 dev Bean 구성

Java 21로 컴파일 후 JUnit ConsoleLauncher: 신규 14 + 기존 76 = 90 성공, 0 실패.
전체 Gradle은 작성 환경의 플러그인 해석 제약으로 실행하지 못했다.
Windows에서 Apply-P06-04.ps1이 clean test bootJar를 실행한다.
실제 MySQL 환경에서는 새 DB에 V1~V7을 적용하고 동시 첫 로그인/롤백/DELETING 거부를
동일하게 확인해야 한다. 아직 실공급자 로그인과 휴대폰 UI 연결은 없다.

## 다음 단계

P06-05 접근/갱신 토큰 및 세션 발급. 이번 결과(userId/deviceId)를 연결한다.

## 참고

https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/support/TransactionTemplate.html
