# P12-08 검증 자원 제한 (원수)

## 범위·근거·모델
- 사용자 P12-08까지 원수 승인, 요청 모델 gpt-6.1-sol/medium. 최초 begin으로 구독 사용량 시작값 저장. legacy 기본 Astra 표기는 현재 작업의 명시 요청으로 교정하고 관측값은 별도 유지. 추가 AI·Worker/Reviewer 호출 없음.
- 원본 계획 v1.0 XML p00663~665, 설계 v1.11 p00494~498 원본 읽음. R071 자원 제한 부분. P12-07 7305a67 및 실제 CI/실기 완료 유지. 시작 시 main/원격 ff55e21ff4e28e96347da9a86dcf08c7206ef92b 동일, 기존 미커밋 기록 보존.
- P12-09 최종 객체/DB 확정은 미승인·미착수. 전체 P12 완료로 확대하지 않음.

## 변경
- ValidationBudget: 다운로드·프로브·전체 디코딩에 하나의 60초 예산, 초기 단일 worker 프로세스 전체 2개 슬롯. 중첩 검증의 시간/슬롯 새로 시작 금지. 시간 초과 후 남은 다운로드 reader가 종료될 때까지 슬롯 유지.
- UploadVerification: 상한 6MiB+1 읽기 중단 유지, 블록된 read를 deadline Future와 abort/cancel로 중단. 소비자 실행 전에 lease 및 시간 대조, 실패 후 무기한 대기/성공 반환 없음. 다운로드 네트워크 호출은 기존 SDK 20초 상한도 유지.
- AudioValidator/UploadWorkerConfiguration/리소스 audio/sandbox.py: native 메모리 512MiB OS 제한. Windows Job Object의 process/job committed memory, Linux RLIMIT_AS. FFmpeg 할당 16MiB, probe 보관 64KiB, PCM은 최대 샘플 수 계수만. 도구 stderr 보관/출력 없이 메모리 실패 고정 분류. 제한 적용 실패에 무제한 실행 우회 없음. helper·하위 프로세스 종료 및 자기 파일 정리.
- 제한 초과 FILE_VALIDATION_TIMEOUT, 슬롯 포화 UPLOAD_WORKER_BUSY, 다운로드 과대 UPLOAD_TOO_LARGE, 환경 FILE_SANDBOX_UNAVAILABLE/FILE_VALIDATOR_UNAVAILABLE. 정상/자산 STORED 확정하지 않음.
- 운영 범위·플랫폼별 한도·Python/FFmpeg 실행 환경: services/api/UPLOAD-VALIDATION.md. JVM 전체 힙/여러 worker 분산 제어로 확대하지 않으며 초기 worker 1개 배포 조건을 명시.

## 실행 검사와 별도 검토
- 초기 연결 회귀 `test --tests '*AudioValidatorTests' --tests '*UploadCompletionTests'`: PASS(39초).
- OS 메모리 실제 768MiB 할당 거절, 출력 1MiB를 1KiB 계수 한도로 중단, 20초 대기 child를 2초에서 종료·실제 PID 생존 없음, 다음 프로세스 정상 실행, 도구 없음 거절, 전체 2개 슬롯/중첩 공유/블록된 다운로드 abort 검사 PASS.
- 일괄 `services/api/gradlew.bat -p services/api test bootJar r2CheckerClasspath --offline --console=plain`: 585 중 515 PASS, 70 MySQL 조건부 SKIP, 패키징/검사 classpath PASS(56초). 제외 70개는 실제 CI로 보완하며 로컬 PASS로 계산하지 않음.
- 현재 모델 별도 검토에서 timeout 후 reader 정리 전에 슬롯을 반환할 가능성을 보강. root/reader 참조로 실제 종료까지 유지, 중복 release 거절 검사 추가. 이후 관련 `ValidationResourceTests + UploadCompletionTests + bootJar`: 10 PASS(14초), 회귀/패키징 PASS. 실제 SDK abort는 현재 구현 경계 사용, 임의 close 불응 스트림까지 강제 종료한다고 주장하지 않음.
- 저장한 개발 worker 키로 `r2_credentials.py --use-stored-role dev.worker --audio-check`: PASS(2026-10-08T23:41:57.545135Z). 실제 R2 다운로드·정상 검증·손상 거절·동일 바이트 보존·시험 객체 정리. 키/암호문 읽기·출력·사용자 재입력 없음.
- 원수 사용량 모델 반영 검증 7 PASS. 새 테스트의 Windows 기본 문자 인코딩 오류 1회는 UTF-8 읽기 명시 후 해결, 제품 코드 실패로 합산하지 않음. 이 측정 연결 파일의 기존 미커밋 변경은 보존하며 제품 커밋에 섞지 않는다.
- 현재 모델 직접 원본 완료 조건·실제 diff·검사 결과·업로드 계정/lease 보호·오류 분류·메모리/출력·프로세스 정리·기존 데이터 보존을 대조. 별도 모델·에이전트 없음.
- raw 검사 로그/요약은 `.local/workflow/p12-08/`, 키/사용자 녹음 원본 없음. 폰 조작 필요 없음.

## 남은 조건
검증한 연결 변경 커밋·푸시 후 최종 SHA의 필요한 서버·DB CI. 전체 변경 BaseCommit은 ff55e21ff4e28e96347da9a86dcf08c7206ef92b. P12-09 이후 미착수.

학습 개념: 입력 크기만 작아도 디코더가 큰 메모리나 긴 시간을 소비할 수 있다. 바이트 상한과 별개로 OS 프로세스 한도·출력 계수·공유 시간 예산을 두며, 제한에 걸린 작업을 정상으로 확정하지 않는다.
