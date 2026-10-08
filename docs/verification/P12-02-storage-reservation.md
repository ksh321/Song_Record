# P12-02 개인과 전체 용량 예약 — CI 대기

- 승인: P12-03까지 원수 순차, 현재 대화 Astra/medium. P12-01 SHA 5557ec5 및 필수 CI PASS 후 시작. 별도 AI 호출 없음.
- 원본 계획서 p00645~647, 설계서 p00443~463/p00739 확인. 계정 1,000,000,000 / 전체 20,000,000,000바이트 기본 DB 한도 사용. R068, V14.
- UploadReservations: 기존 recording_upload/storage_usage/global_storage_usage 재사용, 글로벌→사용자 동기화→요금제→사용량 순서의 잠금. 합계 오버플로를 막는 차감 비교. 한도 감소로 기존 used가 초과되어도 삭제하지 않고 새 예약만 거절.
- 활성 동일 녹음은 기존 예약 반환. 새 예약 행/개인·전체 예약량 및 revision이 한 트랜잭션에서 기록. 실패 시 모두 롤백. DB 슬롯 제약과 6MiB 제한 유지. R2 호출/물리 파일/앱 변경 없음.
- HTTP 승인 연결·대상/파일 명세/속도 제한은 P12-03, 예약 해제·최종 확정은 후속 원본 단계. 이 내부 DB 기반 구현을 공개 업로드 API 완료로 표시하지 않음.
- 검사: `gradlew test bootJar` 성공. {'tests': 560, 'failures': 0, 'errors': 0, 'skipped': 68}. 조건부 MySQL 검사는 로컬 통과로 계산하지 않음.
- H2 및 기존 MySqlIdempotencyTests CI에 동일 검사 연결: 개인/계정 간 전체 경계 동시성, 기존 예약 재조회 무증가, 다른 계정 자료 거절, 외부 트랜잭션 실패 후 행/두 카운터 롤백, 예산 잠금/정수 최대값/음수 입력.
- 현재 모델 별도 검토: 잠금 후 조회도 FOR UPDATE로 기존 REPEATABLE READ 스냅샷을 피함. 덧셈 대신 quota-used-reserved 비교, revision 초과 시 변경 전 실패, 글로벌 직렬화와 계정 격리 유지. 신규 DB/기기 실기 없음; 실제 InnoDB 경계 검증은 CI 필수.
- 로컬 로그 .local/workflow/p12-02/local-check.log. 커밋·푸시·필수 CI 후 완료 예정.
