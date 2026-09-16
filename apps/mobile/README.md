# Flutter Android 앱

P01-01에서 앱 위치를 예약했다. Flutter 프로젝트 생성·의존성 해결·실행은 P01-02에서 수행한다.

- 기술 기준: [D01](../../docs/decisions/D01-implementation-stack.md), [버전 목록](../../docs/contracts/toolchain-versions.md)
- 화면 기준: [원본 자료](../../docs/reference/)
- 공통 데이터: [fixtures](../../fixtures/README.md)
- 프로젝트 생성 위치: 저장소 루트 기준 `apps/mobile`. 생성 시 이 README는 유지·갱신한다.
- 서버 DB·R2 비밀값을 앱에 넣지 않는다. 개발/검증/운영 API 주소 구분은 P01-02에서 구성한다.
- 앱 `pubspec.lock`, Android Gradle Wrapper는 추적한다. SDK 로컬 경로·서명 키·빌드 결과는 제외한다.
