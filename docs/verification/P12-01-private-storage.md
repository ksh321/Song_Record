# P12-01 비공개 저장소 연결 — 완료

- 승인: P12-03까지 원수 순차 진행. Astra/medium 현재 대화 직접 작업. 별도 AI 호출 없음.
- 원본: 계획서 v1.0 p00642~644, 설계서 v1.11 p00475~494 및 p01121; R001/R068~070. 개발·운영 버킷과 자격 증명 분리, attempt 임시 키와 generation 최종 키, 앱에 비밀키/최종 쓰기 권한 금지.
- 시작: 2026-10-08T06:17:24.703128+00:00 최초 구독 조회 잔여 27%. 실제 turn 01a11a28-82d9-7203-b0a0-4528b662d740, gpt-6-astra/medium. manual_usage begin으로 자동 집계 연결. 기존 시작값 유지.
- Git main, 로컬/새 원격 조회 bd5d4c05e8f5590312b334cda045a03d782f8348 일치. 기존 문서·사용량 도구 변경 보존, 중복 제품 실행 없음.

## 준비한 변경
- services/api/src/main/java/com/ksh321/songrecord/api/storage/: 서버 전용 R2 설정/연결 빈, 역할 경계, UUID 기반 임시/최종 객체 키.
- 개발·운영 및 임시·최종 버킷 명칭 분리. API는 임시 버킷 전용 토큰, worker는 해당 환경 두 버킷 전용 토큰을 주입하도록 구성. 다른 환경·역할 자격 증명으로 대체하지 않는다.
- 미설정 기본 비활성, 명시적 활성화 시 필수 설정 누락 거절. HTTPS 공식 R2 endpoint/auto region/path style/chunked 비활성/시간 제한. 설정/오류에 비밀값 출력 안 함.
- build.gradle/gradle.lockfile: AWS SDK 2.55.12 고정. 명시적 URLConnection만 사용하고 사용하지 않는 Apache/Netty 전송 제외. 기존 종속성 버전 유지.
- services/api/R2-SETUP.md: 설정과 실제 환경 검증 절차. R2StorageTests: 6개 회귀/설정/역할/키 검사.

## 실제 검사·검토
- `services/api/gradlew.bat -p services/api test --write-locks --console=plain`: 550개 중 483 PASS, 67 환경 조건부 SKIPPED, 실패 0. 로그 .local/workflow/p12-01/local-check.log.
- 검토 후 불필요한 전송 의존성 제외. `dependencies --write-locks`로 런타임 포함 잠금 저장 후 `bootJar test --tests '*R2StorageTests' --console=plain`: 패키징 및 6개 검사 PASS. 로그 dependency-lock.log/package-check.log.
- 현재 모델 별도 코드 검토: 임의 파일명/경로 대신 UUID 키, 환경/역할 혼용 거절, 비밀값과 provider 오류 마스킹, 앱 변경/자격 증명 포함 없음. H2 및 합성 자격 증명 검사이며 실제 R2 통과가 아님.
- HEAD 성공만으로 비공개/권한 격리 판정하지 않는다. 실제 제공자 설정과 API 토큰의 최종 버킷 거절, worker 허용, 환경 분리를 추가 대조해야 한다.
- 학습: 서명 URL은 임시 객체에만 권한을 주고, 검증한 바이트의 최종 객체는 다른 경로와 worker 권한으로 분리해야 재사용 PUT이 최종 파일을 덮어쓰지 못한다. URL/검증/쓰기 연결은 후속 원본 P번호 범위다.

## 차단·재개
- 사용자 회신: R2 버킷과 자격 증명 아직 없음. 환경변수의 R2/SONGRECORD_STORAGE 설정도 없음(값 미출력).
- USER-041: Cloudflare 로그인 후 R2 화면 상태 확인. 신규 결제/서비스 활성화는 자동 수행하지 않음.
- 브라우저 제어는 sandbox helper 오류로 접근 실패. Codex 패널 열기 요청은 queued이며 실제 로그인 화면 확인 근거가 아님. 추정 버튼 조작을 지시하지 않음.
- 로컬 구현만 완료, P12-01 전체 미완료. 코드/문서 미커밋, 푸시/CI 미실행. P12-02/03은 앞 번호 완료 전 미착수. 실행 중 제품 프로세스 없음.
- 실제 연결·권한 검증 후 현재 diff 검토→커밋·푸시→필수 CI→P12-01 완료/사용량 finish→P12-02 begin. 현재 사용량 시작값은 재개까지 유지한다.

- 후속 사용자 동의: 개발 테스트용으로 진행하고 공개 운영 전 사용량 제한·비용 알림 준비. USER-041 판본2로 R2 구독 활성화 버튼 안내. 브라우저 도구는 trusted Node 종료로 재접근 실패. 실제 활성화/결제 여부는 미확인.

- 2026-10-08 사용자 R2 활성화 완료 회신. USER-041 처리, 버킷/서버 자격 증명 및 실제 권한 검증은 미완료.

- 후속: 화면 제어 두 도구 모두 sandbox helper 오류. Git 제외 .local/workflow/cloudflare에 npm 12.2.0/Wrangler 4.148.0 준비. 목록에 R2 전용 OAuth scope 없음. account:read/user:read/workers:write 로그인 명령은 권한 범위 초과로 자동 승인 거절되어 미실행. 우회하지 않음. USER-042 최소 R2 권한 방식 또는 넓은 OAuth 권한 명시 승인 선택 대기.

- 사용자 버킷 4개 생성 완료 회신. 생성 안내의 4개 범위에 대한 사용자 확인이며, 실제 이름·비공개·권한은 연결 후 대조 예정. R2 전용 키 입력용 Git 제외 로컬 파일 준비(비밀값 미출력).

## 키 입력 절차 변경
- 사용자 평문 입력 후 삭제 회신. 해당 파일의 실제 값은 읽지 않음. 이전 평문 입력 안내 폐기, 기존 토큰 취소 및 새 키 사용 안내.
- tools/r2_credentials.py: 마스킹 GUI, 역할별 DPAPI 암호화, Java 검사에 stdin 전달, 고정 상태/시각만 파일에 기록. 같은 Windows 사용자에 대한 접근 차단을 보장하지 않음을 명시.
- 가짜 키 Python 검사 5 PASS: 암호화/역할 오용 거절/저장·기존 결과 무효화/stdin만 전달/결과 허용 목록/오류 비노출. Java R2StorageTests 7 PASS 및 실제 자식 프로세스 잘못된 입력 CHECK_ERROR 고정 출력 확인. 실키 검사 미실행.
- 새 GUI는 사용자 직접 입력·검사 대기. AI는 vault/기존 평문 파일/프로세스 메모리/클립보드를 조회하지 않고 보고서만 읽는다. 검사 범위는 연결·읽기 권한 분리이며 쓰기·공개 접근 검증은 별도다.

## 현재 유효: 일회용 입력 전환
- 사용자 요청으로 DPAPI 저장/복호화 기능 제거. 마스킹 입력→입력란 즉시 비움→Java stdin 검사→고정 결과만 기록. 과거 키 파일은 읽지 않음. 메모리/OS/클립보드 완전 삭제 보장 아님.
- 가짜 키 Python 5 PASS: 자격 증명 파일 생성 없음/기존 vault 읽기 금지/stdin만 전달/실패 시 과거 PASS 제거/오류 원문 차단/권한 결과 필터. Java 검사 로직은 변경 없음.
- USER-043 판본3 실제 키 일회용 검사 대기. 실제 키 읽기·검사 결과를 추정하지 않음.

## 실제 읽기 확인 및 남은 검사 준비
- 사용자 검사 완료 회신. dev.api/dev.worker/prod.api/prod.worker 4개 보고서 PASS(2026-10-08 07:40~07:43 UTC). API는 자기 temporary만 허용, worker는 자기 환경 두 버킷 허용, 다른 환경 모두 거절. 키 파일/메모리/클립보드 읽지 않음.
- 새 원격 main과 로컬 HEAD bd5d4c05e8f5590312b334cda045a03d782f8348 일치. 기존 자동 실행 checkpoint는 P10-08 종료 상태이며 현재 원수 승인 범위는 P12-03까지 유지.
- DevelopmentStorageProbe 및 GUI 개발 쓰기 모드 추가: 개발 고유 합성 파일만 PUT/GET/비서명 GET/DELETE, API final PUT 거절 확인. 운영 쓰기/기존 객체 충돌 시 삭제 방지. 읽기 보고서 보존, 별도 결과만 저장.
- Python 6 PASS. Java R2StorageTests 7 + DevelopmentStorageProbeTests 6 PASS, checker classpath 재생성 성공. 최초 테스트 컴파일에서 SDK ResponseBytes의 없는 메서드를 사용한 오류는 fromByteArray로 수정 후 통과(합성 테스트 API 오류 1회, 동작 실패 아님).
- 현재 모델 별도 검토: PUT 거절과 PUT 후 GET 거절을 분리, 412 충돌 삭제 방지, 응답 유실 정리 시도, 정리 실패 통과 금지, prod 검사 거절, 공개 도메인 검증 별도 유지. 실제 쓰기 결과는 아직 없음.
- USER-043 완료 처리. USER-044 사용자 키 재입력 및 공개 설정 확인 대기. 미커밋 변경 보존, 제품 CI/푸시 미실행, P12-02·03 미착수.

## 개발 검사 실패 진단 — P12-01-PROBE-AUTH-STATUS
- 사용자 dev.api 실패 회신. 해당 시도 보고서는 읽기 4개 정상, final PUT DENIED, temporary 추가 검사 ERROR. 같은 입력으로 인증 읽기가 성공했으므로 키 오류로 판정하지 않음. 임시 객체 정리 실패 상태는 아님.
- 기존 도구가 PUT/GET/비서명 응답을 ERROR 하나로 기록한 한계와 권한 범위 불일치라는 부정확한 UI 문구 수정. 단계와 HTTP 숫자/고정 오류 분류만 기록하고 원문/키는 출력하지 않음.
- 키 없는 독립 HTTP 요청에서 R2 응답 400, Code=InvalidArgument, Message=Authorization 확인. 403만 인정하던 도구 판정 문제 발견. 실제 과거 실패 단계는 기록 부족으로 확정하지 않음.
- 인증된 PUT·GET 바이트 확인 후 비서명 GET의 403 또는 400+정확한 InvalidArgument/Authorization만 인정. 일반 400/성공 응답/다른 오류는 실패 유지. XML은 4096바이트 제한 및 DTD/외부 엔터티 금지. 공개 도메인 별도 확인 조건 유지.
- 실제 재검사 대기. 이 도구 판정 문제의 실키 분석·수정·재검증 실패 횟수는 아직 재검증 전이며 과거 컴파일 오류와 합산하지 않음. 키 교체 불필요.

- 수정 후 Java 14 / Python 6 PASS, diff 공백 검사 통과. 사용자 일회용 입력 대기.

## 수정 후 실제 개발 검사 통과
- 사용자 완료 회신과 dev.api 07:56:59 UTC / dev.worker 07:57:25 UTC 보고서 PASS 대조. 임시 객체 쓰기·동일 바이트 읽기·비서명 접근 차단·시험 객체 정리 확인. API final 쓰기는 DENIED, worker final 쓰기는 VERIFIED. 환경별 읽기 격리도 유지.
- 실제 재검증으로 도구 응답 판정 수정 통과. 비밀키는 읽지 않았으며 현재 결과만 확인. USER-044의 개발 검사 2개는 완료, 공개 URL/Custom Domains 설정 확인 회신은 별도 대기.

- 최종 일괄 로컬 검사 `gradlew test bootJar`: {'tests': 558, 'failures': 0, 'errors': 0, 'skipped': 67}; PASS 491개, 조건부 skip은 통과로 계산하지 않음. 로그 .local/workflow/p12-01/final-local-check.log. 패키징 성공. 현재 모델 검토: 앱에 자격 증명 추가 없음, 환경/역할 분리와 키 경계 유지, 실제 개발 합성 검사 PASS. 사용자 공개 설정 미확인 회신으로 필수 확인 대기, 미커밋 및 원격 CI 미실행 유지.

## 실제 환경 최종 확인
- 사용자 첨부 사진: 사용자 지정 도메인 없음, 공개 개발 URL 사용 버튼(비활성 상태). 4개 버킷 모두 같다는 명시 확인. USER-044 완료.
- 실제 개발 API/worker 합성 쓰기·읽기·삭제·비서명 차단과 환경/역할 읽기 격리 PASS. 운영은 읽기 격리·비공개 설정만 확인했으며 운영 쓰기/배포 없음.
- 로컬 558개: 491 PASS, 67 환경 조건부 SKIP, 실패 0; bootJar 성공. 현재 모델 별도 검토 완료. 미확인 MySQL 조건부 검사는 필수 CI에서 확인 예정.
- 이번 커밋은 P12-01 코드·설정 안내·검증·일회용 검사 도구만 포함. 이전부터 존재하는 워크플로우/사용량/과거 P번호 변경은 보존하고 섞지 않음.

## 최종 완료
- 대상 SHA 5557ec5e55484b3743e2be6cc74d4596e7993d12, Base bd5d4c05e8f5590312b334cda045a03d782f8348. CI 37747601935 및 Idempotency MySQL 37747601820 PASS. 영향 없는 계약/워크플로우 CI는 NOT_APPLICABLE(통과 개수 제외).
- 필수 로컬·실제 R2·비공개 설정·현재 모델 검토·푸시·CI 근거 충족. 기존 감시가 CI PASS 폰 알림 서버 접수 확인, 휴대폰 수신 자체는 미확인. P12-01 완료, 승인된 다음 P12-02로 진행.
