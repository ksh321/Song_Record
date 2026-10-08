# P11-01 보관 후보 조회

## 범위와 근거
- 코드구현계획서 v1.0 P11-01(p00610~p00612), 구현설계서 v1.11 6.1, R052의 후보 자격 부분을 구현한다.
- 같은 사용자·곡의 ACTIVE/SAVED 녹음 중 유효한 완료 파일 명세만 조회한다. 다른 기기에만 존재하는 파일도 포함한다.
- DRAFT, 손상·누락 명세, 휴지통·영구 삭제 상태, 다른 계정·곡을 제외한다. 탈퇴 중 계정과 비활성 곡도 제외한다.
- 역할 선정·3개 제한·재계산·고정 슬롯·물리 파일 조작은 후속 P11 범위이며 이번 완료로 확대하지 않는다.
- 선행 녹음 저장·편집 및 동기화의 기존 완료 근거를 유지한다. 새 HTTP API 없이 신뢰된 서버 내부 호출자가 인증된 소유자를 제공하는 조회 컴포넌트다.

## 변경
- RetentionCandidates.java: 계정·곡·상태를 제한한 읽기 전용 조회, 기존 저장 계약과 동일한 파일 명세 검증.
- RetentionCandidatesTests.java 및 RetentionCandidateDatabaseChecks.java: 경계·다른 기기·불변 결과·UTC 시각·손상 명세·조회 무변경 검사.
- MySqlIdempotencyTests.java: 전체 마이그레이션을 적용한 격리 MySQL DB에서 동일 자격 검증을 수행한다. 사용자 개발 DB는 건드리지 않는다.

## 로컬 검증과 검토
- services/api에서 Gradle test --offline --no-daemon, RetentionCandidatesTests/RecordingSavingTests/RecordingEditingTests/RecordingDraftTests 선택: 24개 통과, 실패·건너뜀 0. 실제 실행 27초.
- 사용량 보고서 회귀: tools/tests/test_workflow_usage.py 17개 통과. 자동 측정과 사용자 확인을 구분하며 미집계 호출 수를 0으로 표시하지 않는다.
- python tools/index_sources.py --check: 원본 6개 해시 확인 통과. git diff --check 통과.
- 현재 대화 모델이 구현 후 별도 코드 검토: 원본 완료 조건, owner/song JOIN, 파일 계약 경계, 데이터 무변경, 다른 기기 포함 및 후속 범위 분리를 대조했다. 별도 모델/에이전트 호출 없음.
- 서버 내부 조회만 추가하여 폰 실기 불필요. 실제 MySQL 실행은 Docker 엔진이 없는 로컬에서 통과로 간주하지 않고 필수 CI로 확인한다.

## 커밋·CI 및 측정
- push 전 새 원격 main 조회 기준: fcb28873f763bf7d1b07a5131d61db20abcff6cf.
- 커밋 시점 필수 CI는 대기. 대상 SHA·실제 결과는 후속 완료 기록에서 확정한다.
- P11-01 (원수), 자동 측정 시작: 2026-10-08T02:39:46.905585+00:00, 주간 사용 55% / 잔여 45%.
- 사용자 요청에 따라 완료 알림 처리 결과까지 시간을 재고 직후 공식 한도를 다시 조회한다. 메시지 도착 순간의 과거 값을 복원한 수치가 아니며 계정 전체의 같은 기간 차이다.
- P11-02는 승인되지 않아 시작하지 않는다.
