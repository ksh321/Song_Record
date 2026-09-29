# P06-02 Google 증명 검증

> 현재 상태 (2026-09-29): **기존 기능 사용자 검증 완료**. 기준 HEAD와 확인 원문은 [사용자 확인 기록](../progress.md#user-acceptance-20260929)을 따른다. 아래 검증 대기/미실행 표현과 체크리스트는 당시 이력이며, 문서 부족만으로 재실기를 요청하지 않는다. 개별 사례의 실행 횟수·명령·기기를 새로 확인한 것으로 기록하지 않는다. 이후 변경과 영향 범위는 별도로 검증한다.

기준 main: `2454e255516f08dbac0f23ddd33373980415809f`.
상태: 사용자 Windows 전체 빌드 성공 보고 및 main `f00c9aff403c4803e90c54f8bca4171c1f5d8e9f`의 CI `35941093595` 성공 확인. P06-02 완료.
P05-08은 사용자 실기 6항목 정상 및 위 커밋의 CI 35863481019 성공으로 완료 확인했다.

## 동작

- Nimbus JOSE JWT 10.9의 서명 검증기를 사용한다. RS256만 허용한다.
- Google 고정 HTTPS JWKS 주소의 공개키만 신뢰한다. 토큰의 jku/x5u를 따라가지 않는다.
- 발급자 2종, 단일 Web/server audience, 비어 있지 않은 sub, exp/iat를 확인한다.
- exp는 현재 시각과 같아도 만료다. 미래 iat/nbf에는 60초 시계 오차만 허용한다.
- 사용자 식별 결과는 GOOGLE + sub다. 이메일로 계정을 찾거나 자동 연결하지 않는다.
- 잘못된 증명: 기존 ApiException 형식의 401 AUTH_INVALID_PROOF, retryable=false.
- 공개키 조회/암호화 인프라 실패: 503 AUTH_PROVIDER_UNAVAILABLE, retryable=true.
- 입력 토큰 최대 16384자, connect/read timeout 2/3초, JWKS 최대 64KiB.
- 키 캐시 5분, refresh 대기 5초, 조회 rate limit 30초. 새 kid는 제한 내 재조회한다.
  제한 중 새 kid를 받으면 잠시 503 후 재시도할 수 있다. 오래된 키 무기한 사용/실패 시 검증 생략은 없다.
- 원문 토큰과 외부 라이브러리 예외/개인정보를 로그나 API 오류에 담지 않는다.
- google-auth profile + GOOGLE_SERVER_CLIENT_ID 환경변수로 켠다. 켰는데 ID가 비어 있으면 시작 실패.
  기존 bootstrap 기본 동작과 SecurityConfig는 유지한다.

## 범위

이번 단계에는 HTTP 로그인 엔드포인트, 계정 DB 변경, 앱 세션 발급, Flutter SDK 연결이 없다.
P06-03 카카오 검증, P06-04 사용자/기기 등록, P06-05 세션, P06-06 앱 연결 순서로 진행한다.
nonce와 일회용 도전값을 요구하는 로그인/재인증 흐름은 후속 서비스에서 검증기에 연결해야 한다.
현재 verify(String)은 계정 연결의 최근 재인증 증명으로 단독 사용하면 안 된다.

## 검증 근거

Amazon Corretto 21.0.12로 새 auth 소스와 기존 ApiException을 javac 컴파일했다.
프로젝트 lockfile과 동일한 Spring Boot 4.1.1 / Spring 7.0.9 / JUnit 6.0.3 jar를 사용해
JUnit ConsoleLauncher로 새 auth 테스트 패키지의 25개 테스트를 실행, 25 성공/0 실패다.
mock으로 서명 성공을 가정하지 않고 로컬 RSA 키로 서명한 JWT와 변조 토큰을 사용한다.
설정 Bean 활성화/비활성화/누락, 허용 발급자, sub, 대상, 필수/만료 시간, unsigned/HS256,
위조 서명/미등록 kid/내용 변조/과대 입력/조회 장애, 키 캐시/교체를 검증했다.
실제 Google 계정 로그인이나 Google 네트워크 조회 성공을 의미하지 않는다.

전체 프로젝트 Gradle은 이 작성 환경에서 Boot 플러그인 resolve 실패로 실행하지 못했다.
Nimbus POM/JAR를 사용한 독립 Gradle 9.7.1 프로젝트에서 lock을 생성했고,
전이 필수 의존성이 없음을 확인해 그 한 줄만 기존 lockfile에 추가했다. 기존 버전은 바꾸지 않았다.
이후 사용자 Windows 전체 빌드 및 CI 성공을 확인했다. 재검증 명령:

```powershell
cd "C:\Users\ksh\Documents\GitHub\Song_Record\services\api"
.\gradlew.bat clean test bootJar
```

## 공식 참고

- https://developers.google.com/identity/sign-in/android/backend-auth
- https://developers.google.com/identity/openid-connect/openid-connect
- https://connect2id.com/products/nimbus-jose-jwt
- https://repo.maven.apache.org/maven2/com/nimbusds/nimbus-jose-jwt/10.9/

P06-01 확인값은 ../auth/P06-01-confirmed-dev-settings.md에 기록했다.
