# P11-04 최저 티어 계산

- 원본 계획 p00619~p00621, 원본 설계 v1.11 6.1, R054를 적용한다. P11-03의 실제 완료 SHA 2f421eae87d2a1e4f4a2accaa75292c040bc2b1f를 보존한다.
- RetentionRoles.lowestTier가 P11-01 유효 후보에서 D→C→B→A→S 순으로 선택하며 null/알 수 없는 티어는 제외한다. 곡 티어를 읽거나 대신 적용하지 않는다.
- 동률은 recorded_at 내림차순, unsigned ID 오름차순으로 결정한다. 파일 위치와 관계없이 동일 입력은 동일 결과이며 데이터 쓰기 없음.
- 변경: RetentionRoles.java, RetentionCandidateDatabaseChecks.java, RetentionCandidatesTests.java, MySqlIdempotencyTests.java.
- 로컬 Gradle test --offline --no-daemon --tests *RetentionCandidatesTests --tests *RecordingEditingTests: 14 PASS, 실패/skip 0, 24초.
- 현재 Astra/medium 대화에서 별도 코드 검토: 티어 우선순위·미정 제외·동률 방향·후보 재사용·읽기 전용 및 기존 역할 보존 확인. 실제 MySQL에서도 같은 검사를 실행하도록 기존 CI 연결.
- 폰 실기 불필요. 저장·selection_revision은 다음 P11-05, 사건 연결은 P11-06 범위다.
- push 기준 새 원격 main: 2f421eae87d2a1e4f4a2accaa75292c040bc2b1f. 필수 CI 결과는 완료 후 아래에 추가한다. 승인 종료는 P11-05.
