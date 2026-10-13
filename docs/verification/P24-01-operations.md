# P24-01 검증 환경 배포

- 원수, 요청·관측 gpt-6.1-sol/medium 고정. 요청 당시 실제 최초 구독 조회 및 rollout/turn 경계 보존. 기준 d268b39fbf418c2d596d8079058b5d83c342d60b, 승인 끝 P24-10.
- 원본 plan/design DOCX raw SHA256와 접근 확인. 계획 p01035–p01037·R120·R125·P23 별도 원장/삭제 실행 계약 및 실제 완료 CI를 대조했다. P24-02 이후 미착수.

## 연결 구현

- 기존 Docker 설치를 실행했다. 엔진29.8.0 연결 확인. 기존 개발 MySQL은 정지 상태로 보존했고 별도 검증 MySQL·전용 볼륨·API·작업자·네트워크를 생성했다. 검증 DB에만 기존 Flyway가 적용된다. 운영/기존 DB 데이터 삭제 없음.
- staging 프로필의 개발/가짜 검색·bootstrap 혼합, HTTP·누락 주소·DB 초기화·버킷 혼합·API 유지보수 역할을 차단한다. 앱 staging/prod은 명시적 HTTPS를 요구한다.
- 기존 계정에 비공개 Standard 검증 R2 버킷2개를 생성했다. USER-096 로그인과 USER-097 세 역할 키는 실제 대시보드/등록 PASS와 회신 범위로 확인했다. 새 API=검증임시RW·작업자=검증임시/확정RW·재생=검증확정RO, 기존 dev/prod4개 거부 및 DPAPI 자동 사용 PASS. 키·발급 성공 화면·원본 사용자 자료를 출력/커밋하지 않았다.
- JAR·Java 실행 이미지와 역할별 메모리 주입/독립 TLS/재개 경계를 연결했다. Java amd64 공식 manifest digest 조회 후 고정. 이미지에 비밀값 없음. 실제 구성/한계/재개는 [검증 배포 실행서](../runbooks/validation-deployment.md).

## 실제 검증과 수정

- 배포 경계4·앱 설정2·키 닫힌 보고서/입력 경계4·실행 상태/기존 DB 보존·TLS 준비 대기4 PASS. Windows 암호화 회귀6 PASS. 최초 제한 환경의 DPAPI 오류는 호스트 접근으로 해결했으며 코드 수정 실패와 합산하지 않았다.
- 실제 검증 MySQL healthy·API/작업자 Started. HTTPS health200·개발 경로404·미인증401·가짜 Google/Kakao503 확인. 실제 OAuth 공급자는 아직 설정되지 않았으며 로그인 성공으로 집계하지 않는다. private localhost 인증서와 실제 공개 도메인은 구분한다.
- 실제 연결 첫 검사는 없는 개발 리소스를500으로 잘못 분류하는 기존 공통 처리 문제를 발견했다. 원인 P24-01-MISSING-RESOURCE, 1회 수정·검증: 원래404인 Spring 예외를404/NOT_FOUND로 반환하고 URI/쿼리/스택을 반사하지 않는다. 영향 테스트5·수정 이미지 재배포·HTTPS 재검사 PASS. 사용자 데이터/검증 DB 유지.
- 연결 구현 후 `.local/workflow/p24-01/checks.ps1` 일괄 검사 PASS: 앱 전체1,204개·분석·staging APK, 도구 및 기존 자격 증명 검사 통과. 최종 서버 build: 총754개, 실패0·오류0·skipped87(통과 실적 제외). 최종 보완 도구8개 PASS. 최신 JAR/배포 이미지 JAR 해시 일치.
- 검증 R2 세 역할 새 UUID 시험 객체 PUT·GET·익명 차단·정리 PASS; API 확정 쓰기/재생 쓰기 및 기존4개 접근 거부. API/worker를 재생성하고 TLS hostname·공개 인증서 검증 health 대기까지 PASS, DB 볼륨 보존.
- 현재 모델 별도 검토 PASS: 원본 완료 조건(배포 환경에서 개발 가짜 인증·검색 미활성화), diff, 실행 결과, 재개·입력 경계·데이터 보존 대조. 실제 OAuth 성공/공개 배포를 완료 근거에 포함하지 않는다. 독립 Reviewer 호출 없음.

## 남은 단계

- 로컬 검사·현재 모델 별도 검토 완료. 명시적 stage·커밋/푸시 및 해당 SHA 필수 CI 뒤 완료 판정. 이후 P24-02. 직접 행동 대기0건.
- 학습: 개발 가짜 데이터는 배포 프로필에서 제거하고, 비밀값·DB·R2 역할·환경·TLS 경계를 각각 확인한다. health 성공은 실제 로그인/복구 성공이 아니다.
