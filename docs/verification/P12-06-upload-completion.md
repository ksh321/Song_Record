# P12-06 — 완료 요청과 검증 작업

## 범위

P12-06까지 원수 승인. P12-05 설치본 7항목·8ecc594 CI 통과 후 최초 측정 begin. finish 직후 집계 잠금 경합 1회는 정상 해제 뒤 재실행, 실행기 중복 시작 없음. 원본 계획 XML p00657~659, 설계 p00481~502·p00889~894, R069. 상세 services/api/UPLOAD-COMPLETION.md.

## 변경

- UploadCompletion/Controller/Configuration: complete 인증·소유권·상태·만료 확인, 멱등 202/기존 COMMITTED 200. 서로 다른 요청 op도 attempt 기준 같은 JobQueue UPLOAD_VERIFY 작업 1개. 영수증·작업 삽입·VERIFYING 상태 전이를 기존 트랜잭션에 연결.
- UploadByteSource/UploadVerification/UploadWorkerConfiguration/R2Storage: worker 역할 streaming GET, 서버 생성 키, 살아 있는 작업 lease·계정·녹음 상태 검사, 실제 바이트의 읽기 전용 전달. 메모리 상한·시간·동시 준비 제한, 과대 스트림 abort. 네트워크는 DB 트랜잭션 밖.
- DB migration 변경 없음. 예약·사용량·파일·녹음 정보 변경/삭제 없음. HEAD만으로 STORED, 준비만으로 job 성공 처리 없음.
- 검증 소비자 경계는 기존 JobRunner에 연결 가능하며 실제 오디오 검증/최종 객체/확정 소비자는 P12-07~09에서 연결한다. 성공 흉내 callback·자동 소비 스케줄러는 추가하지 않았다. P12-07~12 완료로 확대하지 않는다.

## 검사와 별도 코드 검토

- `services/api/gradlew.bat test bootJar --offline --console=plain`: 567개 중 497 PASS, 70 MySQL 환경 조건부 SKIP, 패키징 PASS.
- 검토 보강 후 `test --tests '*UploadCompletionTests' --tests '*R2StorageTests' bootJar --offline --console=plain`: 10 PASS·패키징 PASS.
- 동일 DB 시나리오를 전체 migration MySQL CI에도 추가. 다른 op/동시 complete 작업 1개, 실제 enqueue 후 실패의 작업/영수증 롤백, 다른 계정/상태/만료 거절, 실제 바이트/읽기 전용 뷰, 계정 변경/lease 만료 차단, 과대/미존재 실패, 자산·예약 보존 검사.
- 최초 실패 1: H2 작업 CHECK 생성 연결을 닫은 fixture 수명 문제. 기존 JobTests와 같은 keeper 연결 유지로 수정. 다음 실행에서 이 원인은 해결.
- 별도 실패 2: UTC LocalDateTime으로 저장된 job lease와 기본 시간대 Timestamp 비교 차이. 기존 큐와 동일한 UTC 값으로 조회 수정, 관련 검사 통과. 서로 다른 원인을 합산하지 않음.
- 검토 보강: oversized 응답 close 시 잔여 바이트를 읽을 가능성을 없애도록 SDK abort, worker 설정은 등록 순서에 의존하는 ConditionalOnBean 대신 별도 명시적 enabled/role 구성. 설정 격리 회귀 포함.
- Gradle 대상 검사 옵션을 bootJar 뒤에 잘못 놓은 명령은 실행 전 거절. test 옵션 위치 정정 후 통과; 코드 수정 실패로 세지 않음.
- 현재 모델 직접 별도 검토: 요구사항·diff·실제 결과와 계정 격리/lease/멱등성/보존/후속 단계 경계 대조. 요청 모델 Astra/medium 원수, 별도 모델·에이전트 없음.
- 실제 R2/사용자 녹음 검사는 이번 결과에 포함하지 않는다. 합성 DB 및 SDK 경계 검사이며, 신규 폰 조작 필요 없음. 개발 키 저장/조회 없음.

## 남은 조건

검증한 파일 커밋·푸시 후 필요한 서버·DB CI. MySQL SKIP을 통과로 계산하지 않는다. P12-07 이후 미착수.

학습 개념: 202는 검증 접수이며 파일 보관 완료가 아니다. 같은 시도는 작업 하나로 수렴하고, 임시 객체가 바뀔 수 있으므로 확보한 동일 바이트만 이후 검증·확정에 사용한다.

## 실제 MySQL CI 발견 오류 수정

첫 SHA a4c7037의 서버 CI 통과, MySQL 멱등성 CI 37764986813에서 새 complete의 DATETIME 값을 Timestamp로 직접 cast하여 ClassCastException 발생. MySQL JDBC의 LocalDateTime 반환과 H2 Timestamp 반환 차이가 원인이다. getTimestamp 명시적 RowMapper로 통일하고 같은 위험이 확인된 UploadUrls 조회도 보완했다. 기존 완료 판정을 되돌린 것이 아니라 연결된 현재 코드 오류를 수정했다.

동일 H2/MySQL 시나리오가 실제 URL 재발급→complete 접수를 거치도록 보강했다. `test --tests '*UploadCompletionTests' --tests '*UploadUrlsTests' bootJar --offline --console=plain`: 3 PASS 및 패키징 PASS. 새로운 근본 원인 1회 수정, 다음 SHA 실제 MySQL 재검증 필요. 첫 SHA 실패를 숨기지 않으며 최종 CI 기준은 전체 P12-06 변경 시작 8ecc594를 유지한다.

### MySQL 회귀 fixture 순서 수정
- 8aa9f5e / MySQL CI 37765818656은 fixture가 user_entitlement 전에 pin_slot을 삽입하여 기존 보호 트리거에 거절됨. 제품 제약을 변경하지 않고 권한 생성 후 슬롯 생성 순서로 수정. 날짜 변환과 다른 원인, 1회 수정. 관련 UploadCompletionTests 2 PASS. 로컬 Docker 엔진이 꺼져 있어 실제 MySQL은 CI에서 재확인.
