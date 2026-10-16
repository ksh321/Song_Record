# P25-06 제한 베타 실행 준비

상태: **본인1명 비공개 베타 준비·최종 검토/필수CI 대기**. USER164에서 ‘본인1명으로 먼저 검증’을 선택했다. 현재 환경은 기존 제한 접속 AWS 실험 DB/API/worker이며 실제 음원 포함 백업·격리 복구/해시·디코딩을 확인했다. 노트북 Docker는 별도 검증용으로 보존한다. 외부 참가자 초대·공개 운영 배포는 포함하지 않으며 USER104의 출시 전 추가 실기 조건은 유지한다.

## 참가 범위와 시작 조건

- 운영자가 지정한 초대 대상, 서버 계정 최대20개. AccountRegistrationService의 전역 선행 잠금과 betaAccounts 제한을 사용한다. 임의 가입 허용/공개 모집/외부 초대 메시지는 실행하지 않았다. 실제 참가자와 합성 검증 계정을 구분한다.
- 현재 실제 참가자는 운영자 본인1명이다. 같은 사람의 Google·카카오 두 제공자 계정을 참가자2명으로 세지 않는다. USER164는 현재 제한 접속의 본인 반복 사용 범위를 확정한 것이며 외부 공개·무기한 업로드 잠금 해제·유료 전환 승인이 아니다. R2의 정확한 저장 국가와 일반 이용자 대상 고지·공개 주소/게시 승인은 외부 이용자 확대 전 조건으로 보존한다.
- 먼저 운영자 계정으로 실제 로그인→두 번째 녹음→이전 기록 재생→정보 동기화→업로드/다운로드→삭제/복원/백업을 확인한 뒤 초대 범위를 넓힌다. 동의/정보 처리/삭제 경로가 확인되지 않은 상태로 개인 녹음을 받지 않는다.
- 추가 제조사·지원 하한/최신 OS·새 물리 기기·실제 서비스 복원은 출시 전 미완료 조건이다. 현재 삼성 녹음/합성 복원 통과가 전체 출시 승인으로 바뀌지 않는다.

## 빌드와 설정

| 항목 | 현재 상태 | 다음 조건 |
|---|---|---|
| 실제 beta release APK | 사용자 소유 새 서명, 별도 com.ksh321.songrecord.beta, min24/target36, SHA256 9644f087603784006ed02322a83bc1a019dd6701414064f003042c02a468fefc. 실제 Samsung 설치 hash·Google/카카오 로그인·재실행 대조 PASS | 기존 debug/staging은 보존. 이 APK의 확인은 참가자 배포 승인과 구분 |
| API 주소 | 새 후보는 제한된 AWS공인IP HTTPS·표준신뢰검증PASS(실제주소는 Git제외manifest) | 참가자가 접속할 실제 HTTPS 주소·유효 TLS·가용성/중단 조건 확정 |
| Google/Kakao 로그인 | 사용자 두 제공자 실제 로그인·AWS 유효 세션·계정 분리·재실행 유지 확인, 잘못된 증명401 | 실제 참가자 범위의 접속과 배포 후보 변경 시 영향 확인 |
| 공개 개인정보/삭제 주소 | 기존 두 IP 제한 HTTPS·Google/카카오 실제 소유 확인·미접수 PREPARED 대조 완료 | 개인정보 미확정 항목/공개 게시 승인·실제 공개 상태 확인 |
| 출시 서명 | beta 전용키 Windows 암호화·복구 암호문 검증·폰 암호문 사본 hash 대조 PASS. prodRelease의 미설정 차단 유지 | 복구 암호는 사용자 별도 보관. 다른 PC 실제 키 복원 미실행과 구분 |
| 현재 검증 서버 이미지 | AWS API/worker JAR7d35d66085a0b24efcc3bd985a4b6ea4c8c1d1a7c1ba369756b1b56d8180ebf3·기존 독립DB/3서비스healthy. USER16130일 관측 정책 실제 실행/오류0, 새 UTC 백업 files1·새 격리DB 복원/파일 해시·디코딩 PASS | 최종 검토/커밋/필수CI가 남음. 격리 복원 파일의 물리 기기 재생은 미실행이며 기존 폰 원격 재생 통과와 구분 |
| worker/일일 객체 대조 | USER132 범위 실제 활성화·신선한 대조 문제0·원장 감시·건강 점검 통과 | 실제 음원 검증과 후속 완료 조건 확인, 업로드 잠금 유지 |

공개 로그인 설정과 실제 제한 HTTPS 주소를 넣은 후보 APK의 빌드·콜백·서명과 실제 폰 Google·카카오 로그인을 확인했다. 로그인 통과는 실제 음원 업로드·복구·베타 관찰 완료를 뜻하지 않는다. 개발자 API secret·R2 키를 앱에 넣지 않는다.

staging의 현재 정책 기본값은 계정20·고정10개·개인1,000,000,000바이트·전체20,000,000,000바이트·계정 일일 업로드104,857,600바이트·분당URL10·업로드 동시2·임시536,870,912바이트·worker 동시2다. 실제 entitlement/환경 override는 배포 때 조회해 대조하고 기존 설정·데이터를 초기화하지 않는다.

## 업로드·비용·장애 중단

- 정보 저장·로컬 녹음과 파일 보관 성공은 구분한다. 업로드 활성화는 역할/한도/관측/삭제 경계 확인 후 해당 환경에만 적용한다. 예산 잠금 중에도 기존 정보/로컬 파일/허용된 재생·삭제·백업 다운로드/고정 해제는 유지한다.
- 기존 5만원 알림·6만원 경고·7만원 신규 업로드 잠금을 유지한다. 실제 청구 상한이 아니며 DB/서버/백업 등 비용도 별도다. 새 유료 서비스/결제/리셋을 자동 사용하지 않는다.
- 타인 접근·원본 손실·초과 예약·이전/복원 손실·TJ 혼동·잘못된 기간 게시가 확인되면 신규 초대/가입·신규 업로드부터 중단하고 근거를 보존한다. 실제 계정/파일을 자동 지우거나 DB를 되돌려 숨기지 않는다.
- AWS 실험 서버의 백업/삭제 원장/비용/관측 timer·폰 경고를 확인했다. 노트북 종료 중에도 AWS 실행과 크레딧 소모는 계속되며 AWS Free plan 만료/크레딧 소진 뒤 가용성을 보장하지 않는다. 노트북 native 감시는 별개이고 종료/절전 중 실행되지 않는다. 운영 점검의 release_ready=false를 무시하지 않는다.

## 안내·피드백·연락

운영 연락은 사용자 승인된 공개 문의 주소 happycompanyhaha@gmail.com. 메시지 전송/베타 초대는 별도 실제 대상과 승인 후 수행한다. 참가 안내에는 시험 버전/기기 지원·로컬 보존·정보 동기화와 선택 파일 보관·용량/고정/예산 잠금·외부 ZIP 책임·삭제 경로·중단/복구 연락을 명시한다.

[피드백 서식](beta-feedback.md)으로 앱 버전/OS·단계·기대/실제·재현/회복 여부만 수집한다. 토큰/키/전체 서명URL/원음/개인 메모를 GitHub나 알림에 보내지 않는다. P25-07 관찰은 재방문·두 번째 저장·이전 녹음 실제 재생·고정/보관 상태·복원 문제로 나누며 클릭/URL 발급을 실제 사용자/재생 성공으로 세지 않는다. 합성 계정/에뮬레이터/일회용 CI 데이터는 실제 베타 지표에서 제외한다.

2026-10-16 본인1명 반복관찰: 새10초 녹음·저장/재실행2개·기존 원격재생/새 로컬재생 완료. 고정2/한도10/대기0과 서버STORED2/COMMITTED2·253927B·예약0을 별도 대조했다. 업로드창은 조기잠금했다. 수정 signed beta APK084a540c36c436987ff6edb41eb4079d4ef6d0cfce443f1fca7c9a3e7dcd85b8, 분석/1215검사·실기 통과이며 현재 P25-07 대상SHA 필수CI 대기다. 추가 제조사/복원본 물리 재생·외부공개 조건은 미완료로 유지한다.

## 기존 제공자 설정의 재사용 경계

P06-01 확정 기록의 Google 프로젝트 song-record-dev 및 카카오 노래기록 DEV(ID1586938)를 먼저 사용 여부 확인한다. 개발 로그인 기능은 2026-09-29 사용자 완료 근거를 보존한다. 기존 등록 패키지는 com.ksh321.songrecord.dev이고 베타 후보는 com.ksh321.songrecord.staging이다. 후보 debug 인증서 지문이 기존 dev와 일치해도 패키지 등록을 대체하지 않는다.

서버 Google audience에는 기존 Web/server 클라이언트만 사용하고 Android client ID를 추가하지 않는다. 카카오 서버에는 숫자 앱 ID를 사용하고 native SDK 키와 바꾸지 않는다. staging에는 별도 패키지/정확 서명 등록과 native callback 설정을 대조한 후 주입한다. 새 credential나 권한 확대는 구체적인 범위를 준비해 사용자 승인 후 수행하며 Admin Key/client secret은 이 검증에 불필요하다. 기록의 공개 클라이언트 설정은 실제 콘솔 관측값과 대조하고 토큰/비밀키를 수집하지 않는다.

## 상시 서버 조건 — 사용자 회신 반영

노트북을 꺼도 이용 가능해야 한다. 노트북 Docker 환경은 로컬 검증용으로 유지한다. 베타 API/DB/작업자·운영 백업/비용·상태/삭제 감시는 외부 상시 환경으로 준비해야 하며 현재 Windows DPAPI 키를 암호문 파일 복사만으로 이전할 수 있다고 가정하지 않는다. 원격 전용 역할별 비밀 등록과 별도 보호 저장/복구 계획이 필요하다. 기존 키 출력/운영 권한 확대/사용자 DB 초기화/운영 배포는 실행하지 않았다.

2026-10-14 공식 확인한 후보:
- Oracle Always Free A1: 현재 무료 한도 총2OCPU/12GB. 용량 부족으로 생성 불가할 수 있고 유휴 회수/무료 SLA 부재/카드 본인 확인이 있다. 현재 검증 Dockerfile은 amd64 manifest 고정이므로 ARM 이미지를 별도로 확인·빌드·검사해야 한다. 무료 계정 범위만 사용하며 PAYG 전환/체험판 유료 자원 사용/결제는 자동 승인되지 않는다. https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm https://www.oracle.com/cloud/free/faq/
- AWS Lightsail Linux 공개IPv4 4GB: 월24USD 기본 요금. R2·부가서비스·세금/초과 전송·도메인 등 총비용은 별도이며 계약/카드/자원 생성은 사용자 선택·승인 후에만 진행한다. https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html

현재 메모리 제한 DB1GB/API768MB/worker1536MB와 OS 여유를 고려한 후보 비교다. 동시 부하 성능/실제 월비용을 측정한 값은 아니다. 서버 선택 전 가입·생성·결제·공개 접속·참가자 초대 없음.

### Oracle 무료 가능 여부 확인 결과

USER-109 회신은 무료 가능 여부 확인 승인, 계정 생성·카드 제출·약관 동의·VM 생성·공개 배포 승인은 아니다. 사용자 Oracle 계정 없음 확인.

- 후보: Always Free A1 ARM VM 1대, 총2OCPU/12GB, Ubuntu ARM, 부팅 볼륨50GB(다른 기존 자원 포함 전체200GB 한도 내). CPU/메모리는 월1500OCPU시간/9000GB시간 내, 자국 home region의 실제 Console Always Free 표기를 확인한다. 체험판300달러 크레딧을 상시 무료 자원과 혼동하지 않는다.
- 실제 Docker registry 조회에서 Java eclipse-temurin:21-jre-noble 및 MySQL8.4.11 Linux ARM64 manifest 제공 확인. 현재 amd64 digest 그대로 실행하는 것은 미검증이며 ARM별 고정 digest·이미지 빌드/ffmpeg·실제 MySQL/서비스·복원 부하 검사가 필요하다. .local/workflow/p25-06/oracle-arm64-image-check.json에 공개 digest/시각 기록.
- 실제 계정·지역 용량/할당 가능 여부는 미확인. 공개 문서는 현재 사용자에게 VM 자리가 있다는 근거가 아니다. 계정 가입이 필요하고 공식 FAQ상 카드 본인확인 및 일시 승인 보류가 있을 수 있다. 사용자가 직접 약관/본인 정보/카드 절차를 처리하며 AI가 이를 받지 않는다.
- Free Tier의 유휴 VM 회수 및 SLA 없음 때문에 노트북 독립 운영 후보이지만 무중단을 보장하지 않는다. 회수 방지용 가짜 부하/다중 무료 계정/유료 전환으로 제한을 우회하지 않는다. 백업·관측·복구를 원격 환경에서 따로 검증한다.
- 다음은 가입 진행 여부 선택. 가입 후 Console의 무료 라벨·region·A1 선택/무료 예상 요금까지 읽기로 확인하고, VM 생성/SSH 접근/외부 공개는 정확한 범위 준비 후 별도 실행 승인과 사용자 비밀 입력 절차를 따른다. 결제/업그레이드·유료 자원 생성 없음.

Oracle 콘솔 실제 로그인 후 오사카 활성 지역·A1 계정 서비스 한도16OCPU/96GB(사용0) 확인. FinOps 화면은 체험 구독 사용 기간2026-10-14–2026-11-12/만료2026-11-12를 표시했다. 체험 구독 한도/표시된 크레딧은 무료 A1 월1500OCPU시간/9000GB시간과 다르므로 신규 구성은2OCPU/12GB 이내로 유지한다. root compartment의 인스턴스 목록은 비어 있으며 생성 전 양식 확인 중, 실제 자원/SSH 접근·네트워크 생성 없음.

## 다른 무료 서버 후보 확인 (2026-10-14)
사용자 다른 무료 대안 조사 요청, AWS 계정 과거/현재 없음 회신(USER-115). Oracle 기존 계정/망/키는 삭제하지 않음.
- AWS 신규 고객 Free plan: 초기100USD·활동 추가최대100USD, 6개월 또는 소진 중 먼저 종료. Paid로 전환하지 않는 동안 Free plan 무청구; 종료 시 계정/서비스 중단·90일 후 데이터 삭제 안내. 영구무료/6개월 서버 운영 보장 아님. 실제 계정plan/허용EC2/지역/CPU·RAM·disk·IP·전송 비용/예상 소진 확인 전 구성 확정·VM생성 없음. 현재 구성 보존 임시 검증 후보이며 장기 공개운영 대체완료 아님. https://aws.amazon.com/free/free-tier-faqs/
- Render free: 15분 미사용 절전·free persistent disk 없음·Postgres30일 만료, MySQL+worker 현 구성 보존 불가/공식 production 비추천. https://render.com/docs/free
- Koyeb free: 512MB/0.1vCPU·worker용 불가·영속volume불가·1시간 미사용절전. 현재 API/DB/worker 구성 부적합 추론. https://www.koyeb.com/docs/reference/instances
- Google Compute free: 미국3지역 e2-micro·disk30GB·아웃바운드1GB. 현재 설정DB1GB+API768MB+worker1536MB 합산·OS 여유에 비춰 현 구성 유지 후보로 부족, 비용계정/초과비용 별도. https://docs.cloud.google.com/free/docs/free-cloud-features
- Azure Students: 12개월 내100USD/카드없이 학생자격, 교육·비상업연구·관련개발 목적 조건; 실제 일반 공개서비스 조건 충족 확인 없이 추천하지 않음. https://azure.microsoft.com/en-us/free/students/
현재 후보 AWS의 기간제 한계를 사용자에게 명시, 공식 가입화면Root user email address/AWS account name/Verify email address 준비. 개인정보·비밀번호·인증/약관 가입은 사용자 직접 처리. 계정 생성/크레딧 취득·Paid 전환/VM·배포 미실행. USER-116 직접 가입 진행 또는 영구무료만 선택 대기.


## AWS 실험 서버 생성·관리 접속 검증 완료 (2026-10-14)
USER-117 사용자 명시 승인 후 서울 Free plan에서 Ubuntu24.04 x86_64/c7i-flex.large(2vCPU/4GiB)1대 실제 생성, running 확인. 디스크 gp3 30GiB 암호화/IMDSv2 Required/IAM role 없음·SSH 현재 노트북IPv4 /32 한 규칙 확인. 앱/DB 공개 포트 없음. AWS에는 기존 DPAPI 관리키의 공개 부분만 등록, 비밀키 전송/평문 파일 생성 없음. 식별자/IP/호스트키·raw 운영 결과는 Git 제외 .local/workflow/p25-06에 보관.

인증된 AWS 시스템 로그의 ED25519 공개 호스트키를 고정하고 Paramiko RejectPolicy로 실제 SSH 접속 PASS. 원격 Ubuntu24.04.4 LTS/amd64/CPU2/메모리3813MiB/루트29GiB·잔여27GiB/cloud-init done 확인. AWS 콘솔 시스템/인스턴스 상태 검사 각각 검사 통과, 애플리케이션 상태는 미연결이며 앱 정상 근거 아님.

Docker 공식 apt 저장소 설치·daemon active·Docker29.9.0/Compose5.6.0·hello-world 실행 PASS(exit0). 관리 포트22와 로컬DNS만 listen, 실행 중 제품 컨테이너0. 공식 설치 근거 https://docs.docker.com/engine/install/ubuntu/ . 설치용 공식 저장소만 추가했고 사용자 개발 Docker/DB/감시를 재시작하지 않았다.

서버기본0.09576USD/시간(24시간2.29824USD) 크레딧 차감·disk/IP/전송 별도. Free plan 유지/Paid·Upgrade·추가결제 미실행. 실험 서버는 현재 실행 중이며 노트북을 꺼도 서버 크레딧은 차감된다. 실제 전체 비용/소진일·부하/앱 로그인 통과는 미확인.

현재 모델 별도 검토: 고정 호스트키/RejectPolicy/agent·키파일 탐색 비활성·메모리 DPAPI 복호화·bounded SSH timeout·공식 apt 서명/배포판·arch 검사 대조. 비밀/환경값·원본 부팅로그 출력 또는 Git 저장 없음. 인프라 실행·기록만 변경한 범위의 제품 CI는 NOT_REQUIRED이며 기존 미커밋 앱 변경의 설치본/필요 CI 대기는 유지한다.

다음 경계는 USER-118: 기존 staging.api/staging.worker/staging.playback 3역할 자격 증명을 이 AWS 실험 서버에 전달하는 승인. 목적은 SSH 전용 비공개 앱 연결 검사. dev/prod/백업 키·백업 복구암호·사용자 DB/녹음 원본은 제외. 서버 암호화 EBS의 root 전용0700 폴더/0600 파일 및 역할별 런타임 tmpfs로 배치할 구체안 준비. EBS 암호화는 디스크 유출 보호이며 서버 root 침해 시 해당 키 열람 가능; Windows DPAPI와 동일 보호를 주장하지 않는다. 승인 전 전달/제품 실행·외부443개방·공개배포 미실행. P25-06 미완료/07·08 미착수, 최초 원수 측정 유지.


## USER-118 실행 결과·사용자 내일 재개 중단 (2026-10-14)
사용자 검증용 키3개 AWS전달 명시 승인. 고정호스트키 SSH stdin으로 staging.api/worker/playback만 root0700/0600 파일 전달·내용 일치 PASS. 값 출력/로컬 평문파일/개발·운영·백업키·복구암호·기존DB/개인녹음 전송 없음.

현재 서버 bootJar 빌드 PASS(17초, 실제4task/2실행2up-to-date); 원본 주 Gradle 호출은 sandbox cache/작업경로 환경 오류이며 코드 분석·수정 실패 아님. 기존 캐시/사용자 JVM21에서 재실행 성공. 서비스 소스 기준 b6b860bbebbe4cead554e2db57602ed2f44aeba3, whitelisted jar/Dockerfile/start/inject/compose만 원격 전달, 파일 SHA는 Git 제외 aws-private-deployment.json. 원격 Docker 이미지 빌드 PASS.

독립 프로젝트 song-record-experiment/새 volume/무작위 새 DB·TLS·pagination·karaoke 값은 서버 root 전용 저장; 기존 Windows validation 상태/DB를 복사하지 않음. API·worker는 역할별 tmpfs 주입, Compose up --wait 실제 EXPERIMENT_PRIVATE_SERVICES_HEALTH_PASS/exit0. 기존 MySQL Flyway/JPA/actuator health 포함 시작 성공이며 R2 실제 접근·인증 차단·실제 로그인/업로드/재생·복원 통과로 확대하지 않는다. API127.0.0.1:18443만, AWS 외부 앱/DB 포트 계속 닫힘.

사용자 `내일 작업 이어서 할 거 조치 ㄱ`에 따라 새 검사 중단. 요청 직전에 이미지빌드·서비스 시작 명령 진행 중이어서 해당 bounded 실행 결과만 수집한 후 종료. 새 R2/API smoke·제공자 설정·폰 설치·CI·다음 번호 착수 없음. 원격 /etc/song-record-experiment/user-requested-pause 및 runtime 시작 guard를 저장했다. marker 저장 당시 이미 실행된 start는 종료시 health PASS. 배포 Python50190 exit0, 원수 hook29781 exit0, Gradle94167 exit0. 새 AI/빌드 진행 없음. 기존 노트북 native 감시는 유지하며 노트북 종료 시 감시가 계속된다고 보장하지 않음.

AWS 실험 VM/DB/API/worker는 실행 상태로 보존, 서버 VM 정지·삭제 없음. Free plan 유지·유료 전환 없음이나 VM기본하루약2.30USD 및 디스크/IP등 크레딧 차감은 계속된다. 자동 앱 시작/systemd 재부팅 서비스는 아직 미구현. 키·디스크·기존 데이터·미커밋 앱/문서 보존. P25-06 미완료, 07/08 미착수, 원수 최초 측정·전체 task finish 없음.

내일 재개: 사용자 새 진행 요청 확인 → manual_usage resume 현재 rollout/turn·최초 시작값 보존 → docs/workflow-state/최신 근거/실제 Git·프로세스와 AWS 상태/IP/SSH허용IP 대조 → 고정 호스트키 접속·기존 docker3개/volume/root runtime 존재 확인 → 사용자 중단 marker만 해제 → 현재 원격 state/credentials/DB를 재사용하여 비공개 R2/API 인증 경계 smoke부터 진행. aws-deploy-private.py/키전달/새DB생성을 통째로 반복하지 않는다. 필요 시 기존 이미지/상태로 중단된 서비스만 기동하고 볼륨/키를 삭제하거나 초기화하지 않는다. 이후 공개 OAuth설정/실제 HTTPS·외부접속 승인/폰 실제로그인·설치본/CI/운영백업·감시가 남는다. 추가제조사 등 P25-03 출시 전 조건 유지.

2026-10-15 제한HTTPS 실험: 현재관리망/같은Wi-Fi의443만 허용, 인증전용80·DB닫힘. 무료IP인증서/신뢰검증·6시간자동갱신모의PASS. 현재공인IP/계정키/서버메타데이터/개인자료는 .local에서만 보관. 실제새기기/제공자로그인/원격운영비용·백업/삭제감시·필요CI·실제베타관찰 미완료.

2026-10-15 실제Google로그인: 사용자메인진입확인·AWS Googleidentity1/활성세션1/고아세션0 집계PASS. 현재Google만 확인, 카카오/실제후속사용/계정전환격리·원격운영준비는 대기. 전체베타시작/배포준비완료 판정 아님.

2026-10-15 카카오실제로그인/서버유효세션·Google폐기/별도owner/보존재실행PASS. 서로다른제공자계정2개는실제베타사용자2명이라는뜻이아니다. AWS집계관측실제조회·5분자동timer연결, 원격폰알림/비용·백업·삭제·worker준비는계속대기. 전체베타시작·출시완료아님.

2026-10-15 USER126 승인 두 감시값 AWS전달/실제R2비용조회/비용전용DB갱신/시간당timer/5분최신성·인증서경고점검 PASS. R2추정0KRW는실제조회무료구간이며AWS크레딧·디스크/IP/전송미포함. 별도신규업로드잠금유지·원격백업/복구/삭제원장/worker미연결·release_ready=false. AWS고정Trial 서버접수·USER127폰수신대기, 실제알림수신/완료로추정하지않음.

USER127 판본2사용자 `온다` 회신·AWS원격영수증CONFIRMED_BY_USER로실제폰수신확인. 관측·비용·알림연결은확인했지만독립백업/복구·삭제원장/worker·실제베타검증미완료는유지한다. 새분리백업안은USER128승인전미생성/미전달이다.
