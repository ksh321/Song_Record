# P11-03 최신 역할 계산

- 근거: 원본 계획 p00616~p00618, 설계 v1.11 6.1의 LATEST 규칙, R052/R053. P11-02 SHA12e298f922fae20699a86313badbe22ccaa9fb36 필수 CI 통과 후 착수.
- RetentionRoles.latest는 P11-01의 유효 후보 중 recorded_at 내림차순, 같은 시각에는 recording_id 오름차순으로 1개를 LATEST로 반환한다. 후보가 없으면 빈 결과다.
- UUID 표준 문자열의 순서는 unsigned BINARY(16) 순서와 같다. Java UUID.compareTo의 signed long 비교를 사용하지 않아 7fff/8000 경계에서 역전되지 않는다.
- 파일 위치·생성 순서·revision·티어는 정렬 기준이 아니다. 기록 시각 보정은 다음 계산에 반영된다. 선택 계산은 데이터 쓰기나 파일 조작을 하지 않는다.
- 변경: RetentionRoles.java, RetentionCandidateDatabaseChecks.java, RetentionCandidatesTests.java, MySqlIdempotencyTests.java.
- 로컬: Gradle test --offline --no-daemon, RetentionCandidatesTests/SongRepresentativeTests/RecordingEditingTests. 19 PASS, 실패/skip 0, 25초. 동률 UUID 경계·다른 기기·역순 생성·밀리초 차이·기록 시각 보정·DRAFT 제외·계정 곡 격리·빈 후보·반복 읽기 무변경 확인.
- 현재 Astra/medium 대화의 별도 코드 검토: 원본 정렬 방향, UUID 표현과 DB 비교 일치, 후보 계약 재사용, null 불가 DB 계약, 데이터 보존을 대조했다. 별도 모델 호출 없음.
- 폰 실기 불필요. 실제 MySQL 전체 마이그레이션 검증은 필수 CI에서 같은 사례를 실행한다.
- 역할 합집합 저장·selection_revision은 P11-05, 사건 연결은 P11-06 범위. P11-04는 이번 승인 밖으로 시작하지 않는다.
- push 전 새 원격 main 기준 12e298f922fae20699a86313badbe22ccaa9fb36. 커밋 시 CI 대기, 최종 SHA와 결과는 후속 완료 기록에 남긴다.
