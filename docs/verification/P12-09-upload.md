# P12-09 최종 객체와 DB 확정 (원수)
- 원본 계획 p00666~668, 설계 p00487~498 실제 DOCX 확인. R069/R071/R072/R119. P12-08 cd17d6e 완료 유지, 시작 원격 cd17d6ee380129ba9b031d6adfb8dfebc89f52a0 및 main 일치. 기존 미커밋 기록 보존.
- 요청·관측 gpt-6.1-sol/medium, 현재 모델 직접 구현·별도 검토. 추가 모델/Worker/Reviewer 없음. 최초 원수 begin 유지.
- UploadFinalization/UploadFinalObjects/R2Storage: 검증된 동일 바이트만 사전 final key에 조건부 생성. 기존 generation은 실제 GET 바이트 대조로 재실행하며 다른 내용은 거절. 임시 객체 재조회/복사 없음. 앱/API 역할의 최종 writer 접근 거절 유지.
- 객체 I/O는 트랜잭션 밖, DB 효과는 JobQueue.complete lease fencing 내부. global→user sync→entitlement→usage→aggregate→asset 순서, 현재 계정·녹음·곡 수명·파일 명세·자동/고정/hold 사유·policy revision 재확인. STORED 신규 확정·reserved 해제·used 증가·COMMITTED 및 slot 반환 원자 반영. 기존 STORED/DELETING 대체 없음.
- worker 스케줄 연결은 storage enabled + worker role + upload.scheduling-enabled=true 조건에서만 UPLOAD_VERIFY를 실행. API 프로세스에는 없음. 후속 장애/만료 복구는 P12-10.
- 최초 로컬 검사: 새 lease UTC 비교 오류 1회 수정 후 재검증 통과. 테스트 fixture의 generation은 실제 MySQL BIGINT에 맞춰 UUID 바이트에서 숫자로 교정, 기대값 약화 없음. 테스트 전용 스키마 누락 컬럼 보강.
- 일괄 test bootJar r2CheckerClasspath --offline --console=plain: 총589, 518 PASS, MySQL 조건부71 SKIP, 실패0(57초). MySQL 검사는 실제 CI 후 완료.
- 실제 저장 dev.worker 자동 audio-check PASS: 정상 검증·임시 변경 후 최종 원래 바이트 유지·조건부 동일 재실행·다른 바이트 덮어쓰기 거절·자기 합성 시험 객체 정리. 비밀값 읽기/출력 없음.
- 현재 모델 별도 검토: 원본 조건·diff·검사·계정 및 lease 격리·정책 철회 롤백·이중 계산 방지·기존 원본 유지 대조. docs/기존 정책 파일 미변경. 폰 조작 없음.
- 커밋·푸시 후 최종 SHA 필수 서버/DB CI 확인 대기. 다음 P12-10은 이 작업 완료 후.
- 학습: 최종 객체 작성과 DB 트랜잭션은 한 원자 작업이 될 수 없다. 불변 키·조건부 쓰기·lease 및 상태 재검사·단일 예약 해제로 복구 경계를 만든다.

## 실제 MySQL 검사 발견 보강
- 4941e9f CI 37862992628 신규 fixture가 파일 명세보다 SAVED 전이를 먼저 실행해 실제 DB 보호 trigger가 거절. ENV가 아니라 테스트 준비 순서 원인 ID P12-09-FIXTURE-ORDER, 최초 검증 발견. 명세 삽입 후 SAVED 순서로 교정. 보호/기대값 유지. 최종 SHA에서 필수 검사 재확인.

- 후속 실제 MySQL 37863364705에서 DATETIME Map 값 LocalDateTime 반환과 H2 Timestamp 차이를 발견. 원인 ID P12-09-DATETIME-PORTABILITY. UTC 변환 경계에서 두 타입을 처리하고 같은 Instant 회귀 추가. 준비 순서 원인과 합산하지 않음. DB/테스트 보호 유지.
