# P24-01 노트북 분리 검증 환경

원본 계획 p01035–p01037, R120·R125, 설계서 10.4·14·15장의 검증 환경 준비다. 운영 공개 배포·개인 데이터 삭제가 아니다.

## 실제 환경과 범위

- Compose 프로젝트 `song-record-validation`: MySQL, API, 검증 작업자가 별도 컨테이너다. 기존 `song-record-mysql`과 그 개발 데이터 볼륨은 사용·초기화·삭제하지 않는다.
- MySQL은 `song_record_validation` DB와 전용 named volume을 사용하고 호스트 DB 포트를 공개하지 않는다. API는 노트북 `127.0.0.1:18443`에만 HTTPS로 연결한다. 작업자는 호스트 포트가 없다.
- `staging` 프로필은 dev/bootstrap/candidate-fixtures 혼합을 거부한다. JPA validate·Flyway 검증·clean 금지·HTTPS·역할·버킷 분리를 확인한 뒤 실행한다. 오류 메시지에 설정값을 반사하지 않는다.
- 비공개 Standard R2 버킷 `song-record-staging-dev-temporary`, `song-record-staging-dev-final`을 새로 사용한다. 기존 dev/prod 4개 버킷 접근은 등록 검사에서 모두 거부돼야 한다.
- API 키는 검증 임시 버킷 RW, 작업자는 검증 임시/확정 RW, 재생 키는 검증 확정 RO다. 기존 키를 확대하지 않고 새 역할을 사용한다. API에서 정리·검증 스케줄을 켤 수 없다. 첫 환경 단계에서는 자동 유지보수 스케줄을 비활성화하며 후속 작업에서 검증된 조건으로 연결한다.

## 비밀값과 인증서

- 기존 Windows 현재 사용자 DPAPI와 ACL 도구를 재사용한다. R2 세 역할 및 검증 DB/서명/인증서 암호는 암호화된 Git 제외 저장소에 보관한다. 평문 키를 `.env`, 이미지, Docker 명령 인수, Docker Config.Env, 로그에 넣지 않는다.
- 실행 시 로컬 프로그램이 복호화하여 sealed stdin으로 역할별 컨테이너 tmpfs에 전달한다. 고정 제한의 주입기가 파일명/크기/중복을 검증하고 ready 뒤에만 서버를 시작한다. 프로세스·컨테이너 메모리에는 필요한 값이 존재한다. 같은 Windows/Docker 관리 권한을 가진 프로그램의 접근까지 완전히 막는 보장은 아니다.
- 노트북 전용 localhost 인증서는 14일 유효하고 PFX 개인키는 암호화 저장된다. 검사는 지정한 공개 인증서로 hostname·TLS 검증을 수행한다. 시스템/브라우저 전체 신뢰 변경이나 `badCertificateCallback`, 검증 끄기를 사용하지 않는다. 실제 공개 도메인 인증서의 증거는 아니다.
- DB 볼륨이 있는데 암호화 실행 상태가 없으면 새 암호로 자동 초기화하지 않고 복구를 요구한다. 기존 상태가 있으면 최초 암호/서명 키를 유지한다.

## 실행·재개

AI가 아래 연결을 직접 수행한다. 사용자에게 파일 다운로드·실행을 넘기지 않는다.

1. 서버 JAR과 `infra/validation` 파일만 넣은 전용 빌드 폴더에서 이미지 생성. 검증한 공식 Java amd64 manifest를 digest로 고정한다. 원시 빌드/검사 로그와 실제 이미지 근거는 `.local/workflow/p24-01`에 보존한다.
2. `python tools/validation_runtime.py prepare`: 암호화 실행 상태와 비공개 인증서, 독립 MySQL 준비. 기존 DB 볼륨 삭제·init 복구를 하지 않는다.
3. 사용자 최초 R2 등록은 `tools/validation_credentials.py` 창에서 한 번만 한다. 키/발급 성공 화면을 채팅으로 받지 않는다. 권한·암호화 자동 사용 확인 뒤에만 다음 단계로 이동한다.
4. `python tools/validation_runtime.py connect`: 검증용 stateless API/작업자만 재생성해 새 tmpfs에 주입한다. DB는 그대로 유지한다. 노트북/컨테이너 재시작 후에는 암호화 상태에서 다시 주입해야 한다. 절전 중 서버 운영을 보장하지 않는다.
5. `python tools/validation_runtime.py smoke`: HTTPS health 200, 개발 전용 경로 404, 미인증 me 401, 가짜 Google/Kakao 증명 거부를 확인한다. 전체 연결 검사는 해당 작업의 한 명령 검사 기록을 따른다.

현재 검증 환경에는 실제 Google/Kakao 공급자 설정이 없어 social은 503으로 닫혀 있다. 이는 가짜 인증 차단 실적이며 실제 OAuth 로그인 통과가 아니다. 실제 로그인 공급자·외부 HTTPS 도메인·운영 배포 및 서명/제출 설정은 출시 점검 전에 연결·검증해야 한다. 모바일은 staging/prod에 명시적 HTTPS 주소가 없거나 잘못되면 실행 설정을 거부하며 dev HTTP 기본값으로 대체하지 않는다.

## 다음 번호와 구분

베타/보관/동시성 설정은 P24-02, 비용/관측은 P24-03/04, 실제 암호화 백업과 원장 재적용·복구 훈련은 P24-05–07, 배포/복구 절차와 제출/운영 점검은 P24-08–10이다. health·백업 생성·미인증 오류만으로 실제 서비스 복구나 베타 로그인 성공을 판정하지 않는다. 공개 서비스 배포와 기존 데이터 삭제는 별도 사용자 확인 대상이다.
