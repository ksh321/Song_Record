# P25-02 필수 서버 검증

근거: 계획 p01074–01075, V01–V48 중 서버 책임 범위·D03 UTC 저장 계약. P25-01 최종 c6f7893dc9e69ee6f792e10eb4536ae097a36d39/Development38512044771 및 최초 범위 앱·서버·DB/API/멱등 CI PASS 대조 후 원수 시작. 요청/관측6.1 Sol/medium 고정.

## 격리와 실행

- 새 labelled tmpfs MySQL8.4.11 digest 고정 컨테이너·새 루프백 포트에서 서버 전체 검사를 한 명령으로 실행. 기존 개발/노트북 검증 DB·R2 원본·폰 데이터를 사용/초기화/삭제하지 않음. 무작위 일회용 root 암호는 stdin/tmpfs·자식 테스트 환경에만 전달, argv/보고서/로그에 출력하지 않음.
- MySqlIdempotencyTests의31개 고정3306 연결을 다른 MySQL 테스트의 기존 P10_MYSQL_PORT 설정으로 연결. 미설정 CI 기본3306 유지, 비정상 포트 거부. 테스트 DB는 매번 UUID 이름으로 생성하며 다른 DB 이름을 지정하지 않음.
- 처음772개에서 녹음 후보 UTC 시각1개 실패, MySQL88개 모두 실행/skip0·기기 검사용 대기 프로그램1개 skip. 실패한 새 컨테이너는 근거 확인까지 보존했다. Timestamp→JVM LocalDateTime→UTC 재해석으로00:00Z가09:00Z가 되는 원인을 실제 한국 시간대 JVM과 UTC MySQL에서 확인.

## 수정과 회귀

- ResultSet의 UTC DATETIME을 LocalDateTime으로 직접 읽어 UTC Instant로 변환. 녹음·곡·목록·태그·차트·보관 후보·스냅샷에 같은 위험 패턴을 대조하고 nullable/lease/header 조회도 보완. dev/staging JDBC connectionTimeZone=UTC 및 forceConnectionTimeZoneToSession=true로 쓰기/세션 기준 명시. 기존 데이터의 시각·원본·보정 이력을 일괄 변경하지 않음.
- 새 실제 MySQL 회귀3개: 한국 JVM의 보관 후보 시각 불변, UTC 연결/한국 JVM에서 만료 lease 거부, 스냅샷 header 고정 만료·만료 시점 거부. 각 JVM 기본 시간대는 finally에서 복원. 기대00:00Z/만료 조건·타인 접근/취소·동시성 검사는 완화하지 않음.
- 첫 UTC 수정 뒤773개/실행772/MySQL89 PASS. 별도 현재 모델 검토에서 같은 스냅샷 lease/header 변환을 추가 발견하여 보완 후 전체 재검증. 최종775개 중774개 실행 PASS·실패0, MySQL91개/skip0. 유일한 skip은 DeviceFlowHarnessTests.serveIsolatedDeviceVerification이라는 별도 설치본용 대기 서버이며 서버 책임 검증 통과 수에 넣지 않음.
- 소유권·멱등·관계/FK·충돌/revision·고정/용량·업로드/확정/정리 경쟁·탈퇴/원장·스냅샷 일관성의 기존 실제 MySQL 검사와 추가 회귀를 실행했다. V01–V48의 실기/화면/실제 R2/두 제조사 항목까지 통과했다고 확대하지 않음. 전체 suite/test 결과·빌드/실행 시각·검증 데이터 범위는 보호된 test-inventory.json/실행별 server.log/report.json에 보존.
- 정상 컨테이너와 최초 실패 컨테이너는 각각 해당 run label/ID를 대조해 정리. 실패 XML/로그·기준 시각·문제 기록은 남겼고 기존3개 검증 컨테이너 유지 확인. 삭제 대상은 이 도구가 생성한 합성 일회용 DB 컨테이너뿐이다.

현재 모델 별도 검토: UTC 저장/한국 표시 구분, driver/JVM 조합, 시각 정렬·snapshot lease/expiry, nullable 반환, 기존 파일/DB 불변, 테스트 격리·진짜 실행/skip 구분을 대조했다. 같은 변환 원인으로 기록하고 다른 checkout/참조 문제와 합산하지 않음. 단일 현재 모델 직접 구현/검토, 별도 에이전트·추가 모델 없음.

[Connector/J 날짜/시각 옵션](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-datetime-types-processing.html)과 [시간점 보존](https://dev.mysql.com/doc/connectors/en/connector-j-time-instants.html)의 connection/session 시간대 설명을 확인했다. 저장된 기존 dev 데이터의 과거 작성 시간대는 소급 추정/수정하지 않으며 출시 데이터 점검에서 실제 근거로 대조한다.

로컬 구현·검사·검토 완료, 정확 SHA 커밋/푸시·필수 CI 대기. 다음 P25-03, 현재 직접 행동0건.

학습 개념: DATETIME의 UTC 벽시계 값과 JVM의 현지 시간 변환을 섞으면 같은 숫자를 다른 시간점으로 해석한다. 데이터는 바꾸지 않고 JDBC 읽기·쓰기 기준과 lease/만료 비교를 일치시켜야 한다.
