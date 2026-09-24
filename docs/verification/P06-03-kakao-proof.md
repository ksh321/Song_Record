# P06-03 카카오 증명 검증 및 기존 계정 조회

기준 main: `f00c9aff403c4803e90c54f8bca4171c1f5d8e9f`.
상태: 구현 및 독립 인증 테스트 76개 성공. 사용자 전체 Gradle 빌드 성공 보고 확인. P06-03 푸시/CI는 미확인.

## 코드 위치와 역할

기본 경로: `services/api/src/main/java/com/ksh321/songrecord/api/auth/`

- KakaoProofVerifier.java: SDK access token 검증 결과의 앱 ID, 남은 수명, 회원번호 확인.
- KakaoHttpTokenInfoClient.java: 고정 공식 HTTPS API에 Bearer 헤더로 조회.
- KakaoIdentityLookup.java: 증명 검증에 성공한 뒤에만 기존 AuthIdentity 조회.
- JdbcAuthIdentityRepository.java: provider + provider_user_id를 함께 바인딩하여 조회.
- ProofErrors.java: Google과 Kakao의 오류 형식 공통화. Google 검증 동작 유지.
- KakaoProofConfiguration.java: 선택 profile과 앱 ID 설정, DB 조회 Bean 연결.
- `services/api/src/main/resources/application-kakao-auth.properties`: 활성화 설정.
- 테스트: `services/api/src/test/java/com/ksh321/songrecord/api/auth/`의 Kakao*Tests와 JdbcAuthIdentityRepositoryTests.

## 동작과 제한

카카오 access token을 Google ID token(JWT)처럼 로컬 해석하지 않는다.
GET https://kapi.kakao.com/v1/user/access_token_info 의 성공 응답에서
`app_id`가 설정과 같고 `expires_in > 0`, `id > 0`인 경우에만 KAKAO + 회원번호를 반환한다.
숫자는 정수로 엄격히 읽으며 큰 Long ID도 반올림하지 않는다. 이메일은 식별/자동 연결에 사용하지 않는다.

잘못되거나 만료된 증명은 401 AUTH_INVALID_PROOF, retryable=false.
네트워크 실패, 429/5xx, 잘못된 응답, 카카오 code -1 일시 장애는
503 AUTH_PROVIDER_UNAVAILABLE, retryable=true. Google과 동일한 ApiException 형식이다.
토큰은 URL/로그/예외에 포함하지 않는다. 리디렉션을 따르지 않는다.
연결 제한 2초, 전체 요청/본문 수신 제한 5초, 응답 최대 64KiB, 입력 최대 4096자.
토큰 조회 결과는 캐시하지 않는다.

기존 V2 auth_identity 테이블의 복합 고유키를 사용한다. 신규 마이그레이션과 의존성 변경은 없다.
DB 조회 결과가 없으면 empty로 반환하며 새 계정을 만들지 않는다.
기존 계정 조회는 세션 발급 승인과 다르다. 후속 서비스는 ACTIVE/DELETING 상태를 확인해야 한다.
HTTP 로그인 엔드포인트, 계정 생성, 세션 발급, Flutter SDK 연결은 후속 단계다.
재인증/계정 연결에는 후속 일회용 challenge 검증이 필요하다.

## 설정

`kakao-auth`를 활성화하고 환경변수 `KAKAO_APP_ID=1586938`을 지정한다.
활성화했는데 앱 ID가 없거나 0 이하면 시작 실패한다.
`bootstrap,kakao-auth`는 DB 없이 검증기만 구성한다.
`dev,kakao-auth`는 기존 dev DB 설정과 JdbcTemplate이 필요하다.
기본 bootstrap 검증은 카카오 설정/계정/실토큰 없이 실행한다.

## 검증 결과

Java 21.0.12 및 프로젝트 lock과 같은 Spring Boot 4.1.1/Spring 7.0.9,
Jackson 3.1.5/JUnit 6.0.3으로 인증 소스 컴파일 및 JUnit 실행:
76 성공, 0 실패 (기존 Google 25 + 이번 단계 51).
잘못된 앱/만료/누락/자료형/중복 JSON/과대 응답/HTTP 오류/통신 장애,
실제 loopback HTTP 헤더/리디렉션 차단/본문 수신 timeout을 검증했다.
검증 실패 시 DB 미호출, 정확한 provider+ID 바인딩, BINARY(16) UUID 복원,
중복/손상 데이터 거부, profile별 Bean 구성을 검증했다.
JDBC 테스트는 실제 JdbcTemplate과 모의 JDBC 연결을 사용한다. 실제 MySQL 접속 테스트는 아니다.

작성 환경의 Gradle 플러그인 해석 제약으로 전체 서버 Gradle 빌드는 실행하지 못했다.
사용자 환경에서 `services/api`의 `./gradlew.bat clean test bootJar` 및 이후 CI를 확인한다.
실제 카카오 계정 로그인/공식 API 실토큰 통신은 아직 수행하지 않았다.
휴대폰 UI 테스트는 이번 단계에 없다.

## 공식 근거

- https://developers.kakao.com/docs/ko/kakaologin/rest-api (액세스 토큰 정보 보기)
- https://developers.kakao.com/docs/en/kakaologin/rest-api

다음 단계: P06-04 신규 사용자/기기 등록 트랜잭션.
