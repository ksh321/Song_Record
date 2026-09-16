# Spring Boot API 서버

P01-01에서 서버 위치를 예약했다. Java 21·Spring Boot 프로젝트 생성·실행은 P01-03에서 수행한다.

- 기술 기준: [D01](../../docs/decisions/D01-implementation-stack.md), [버전 목록](../../docs/contracts/toolchain-versions.md)
- API·정책 기준: [요구사항](../../docs/requirements.md), [결정 기록](../../docs/decisions/)
- 공통 데이터: [fixtures](../../fixtures/README.md)
- 프로젝트 생성 위치: `services/api`. 저장소를 이 폴더 안에서 별도로 초기화하지 않는다.
- Gradle Wrapper·의존성 잠금 파일은 추적하고 빌드 산출물·캐시는 제외한다.
- DB 계정 등 비밀값은 런타임 환경 변수로 주입한다. 아직 서버 설정이나 연결을 생성한 상태는 아니다.
