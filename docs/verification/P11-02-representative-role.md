# P11-02 대표 역할 적용

- 원본 계획 p00613~p00615, 설계 v1.11 6.1, R052/R053에 따라 명시된 대표만 REPRESENTATIVE로 계산한다.
- 기존 SongRepresentative의 사용자 지정·해제 API는 유지한다. RetentionRoles와 후보 조회의 대표 전용 조건을 연결해 포인터·계정·곡·유효 명세를 한 SQL에서 읽는다. 대표 없음/부적합이면 빈 결과이며 최신·최고 티어 대체 없음.
- 조회는 읽기 전용. 역할 합집합 저장·selection_revision은 P11-05, 재계산 사건 연결은 P11-06 범위다. 이번에 완료로 확대하지 않는다.
- 변경: RetentionCandidates.java, RetentionRoles.java, RetentionCandidateDatabaseChecks.java, RetentionCandidatesTests.java, MySqlIdempotencyTests.java.
- 로컬: Gradle test --offline --no-daemon, RetentionCandidatesTests/SongRepresentativeTests/RecordingLinkingTests 선택. 16 PASS, 실패/skip 0, 28초. 실제 MySQL 전체 마이그레이션 통합 사례는 필수 CI에서 실행한다.
- 현재 Astra/medium 대화에서 구현 후 별도 검토: 동일 소유자·곡 조인, 포인터와 자격의 단일 SQL 일관성, 대표 해제·무대체·데이터 무변경, 부적합 명세와 재연결 회귀를 대조했다. 별도 AI 생성 없음.
- 폰 실기 불필요: 서버 내부 역할 계산이며 화면·파일 조작 변경 없음.
- push 기준 main f1756e42458c2c5e2fa447fc9139a1eb4ccb91b1. 커밋 시 필수 CI 대기이며 실제 SHA/결과는 후속 완료 기록에 남긴다.
- 원수 자동 측정 begin을 실행했다. 승인 종료 P11-03, P11-02 필수 CI 확인 후 전환한다.
