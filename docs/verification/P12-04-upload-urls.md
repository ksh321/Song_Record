# P12-04 — PUT URL과 재발급

## 상태

2026-10-08 사용자 P12-06까지 원수 승인. P12-01~03 완료 근거 유지. 기준 로컬/새 원격 main: 23f283c1f234063786e15ec09be08a62ec6bd195.
현재 P12-04 구현·로컬 검사·현재 모델 별도 검토 완료, USER-045 실제 개발 R2 서명 PUT 검사 대기. 미커밋·미푸시이며 CI 미실행. P12-05/06 미착수.
사용량 begin은 요청 turn 기준 실행했고 실제 완료 전 finish하지 않는다. 기존 작업/워크플로우 미커밋 변경은 보존했다.

## 근거와 변경

- 계획 원본 XML p00651~653, 설계 원본 p00494·500 및 p00883~888, 오류 표 p01021~1023, R068. 계약 `docs/contracts/P12-upload-urls.md`.
- UploadUrls/UploadController: 실제 승인 HTTP와 renew-url 연결. 계정·소유권·현재 보관 사유 재확인, 동일 시도·24시간 만료 불변, 분당 10회 공동 한도, 멱등 재전송 추가 발급 없음.
- R2PutSigner/UploadPutSigner: SDK 로컬 서명, 임시 키만 10분 PUT. 남은 시도 수명이 짧으면 축소. 서명 실패로 예약·일일량·횟수·영수증을 남기지 않음. 원본 만료 오류 HTTP 410 UPLOAD_EXPIRED 반영.
- R2CredentialCheck/DevelopmentSignedPutProbe 및 tools/r2_credentials.py: dev.api 일회용 입력, 개발 임시 객체만 합성 PUT·재발급 PUT·내용 확인·정리. 키·서명 URL 출력/저장 없음. 운영 쓰기 없음.
- 승인한 URL은 만료 전 재사용 가능하다. PUT 완료를 STORED로 표시하지 않으며 검증 바이트·최종 저장은 후속 번호 담당.

## 실제 검사

- Java21 `gradlew -p services/api test bootJar r2CheckerClasspath --console=plain`: 최종 일괄 564건 중 495 PASS, 69 환경 조건부 SKIP, 실패 0. MySQL 실제 실행은 필수 CI에서 확인 필요.
- 현재 모델 검토 후 원본 만료 상태 HTTP 410 정정: `test --tests '*UploadUrlsTests' bootJar` PASS. 상태 코드 외 구현 변경 없음.
- `python -m unittest discover -s tools/tests -p test_r2_credentials.py`: 7 PASS.
- 기존 `.local/workflow/contract-venv-modern/Scripts/python.exe infra/scripts/verify_api_contract.py`: 기존 OpenAPI/참조/보안·7 wire 예제·141 경계 PASS. 새 업로드 프로토콜 자체는 신규 서버 테스트와 별도 계약 문서로 검증하며 기존 OpenAPI 검사에 포함됐다고 주장하지 않는다.
- git diff --check PASS.
- 새 서버 검사: 실제 SDK 서명 임시 키/TTL/수명 축소, 초기 발급/재발급 멱등, 24시간 불변, 타 계정 차단, VERIFYING 재발급 차단, 보관 대상 철회, URL 한도, 초기/재발급 서명 실패 롤백.
- 검토 방식: 같은 현재 모델이 구현 후 별도로 원본 완료 조건·변경 소스·검사 결과·계정 격리/예약 보존을 대조. 원수 요청 설정 Astra/medium, 별도 AI 호출/검수 에이전트 없음.
- 로컬 요약/로그: `.local/workflow/p12-04/` (Git 제외). 키/서명 URL 없이 기록.

## 사용자 대기·재개

USER-045: 실행 중인 `Song_Record — P12-04 서명 URL 검사` 창(dev.api만)에서 키 일회용 입력. PID 36256, READY와 실제 창 제목 확인. ntfy 서버 접수, 폰 수신은 미확인.
키 미보관이라는 사용자 선택을 유지하므로 AI가 실제 자격 증명을 대신 확보하지 않는다. 사용자의 검사 완료 회신 후 고정 결과 파일 PASS 확인 → 현재 변경 최종 대조 → 커밋·푸시 → 해당 SHA 필수 CI → P12-04 finish → P12-05 begin.
실행기/AI 별도 호출은 없으며 현재 제품 개발은 입력 대기. 검사 GUI만 사용자 입력을 받을 수 있다. 이후 CI 필수 범위는 services/api+docs/contracts 영향에 따라 계산한다.

학습 개념: 주소의 유효기간과 업로드 시도의 수명은 별개다. 주소만 갱신해도 예약 수명이 무한 연장되지 않도록 최초 만료일을 유지한다. 멱등 영수증 재생은 새 주소 발급이 아니므로, 만료된 응답을 받으면 새 요청 키로 재발급한다.

## 실제 검사 회신

USER-045 완료 회신, 개발 signed.temporary VERIFIED/PASS 2026-10-08T09:15:04Z 확인. 초기·재발급 PUT/원본 일치/시험 객체 정리 완료. 사용자 대기 해소. 위 대기 기록은 당시 상태이며 현재 커밋·푸시·필수 CI 단계다.
