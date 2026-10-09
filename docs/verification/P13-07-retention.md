# P13-07 고정 교체 시작 (원수)

- 원본 계획 [p00702]~[p00703], 설계 [p00439]~[p00441], API [p00865]~[p00867], R063/V12 대조. 사용자 지정 gpt-6.1-sol/medium 고정, 현재 모델 직접 구현·별도 검토.
- POST /v1/pins/{slotNo}/replacement는 인증 계정·저장 완료 활성 녹음·base_revision을 확인하고 동일 슬롯 current를 유지하며 pending을 설정한다. 점유 슬롯 수를 늘리지 않는다. 다른 슬롯 중복·진행 중 교체 덮어쓰기·DELETING·다른 계정·미존재·초안·stale revision은 거부한다. 기존 idempotency receipt와 버전 펜스를 재사용한다.
- 교체 시작은 물리 파일 삭제나 용량 확보를 약속하지 않는다. 업로드는 기존 UploadApproval→UploadReservations의 개인/전역 used+reserved 검사를 그대로 거친다. 개인 여유 5MiB에서 6MiB 새 파일은 거절하며 기존 current/10개 슬롯 유지, 전역 여유 부족도 거절, 양쪽 정확한 6MiB 여유면 예약한다.
- 검사: 전체 서버 test/bootJar 614개 중 관련 잠금 정렬 원인2개 실패, 79개 MySQL 환경 skip. 기존 UUID 문자열 순서로 수정하고 PinReplacementTests+PinSlotsTests 영향 검사 전체 PASS11초. 전체의 나머지533개 통과를 보존. 최초 확인/수정1회이며 서로 다른 원인으로 합산하지 않는다. API 계약 검사 PASS(141 경계 사례). 실제 MySQL은 필수 CI 일회용 DB 대기.
- 핵심 검사: 10개 STORED 고정에서 같은 슬롯 current+pending, 기존 보호 유지, receipt 재전송 동일 응답, 타 슬롯 중복·동시 교체1승자·버전 충돌, 개인/전역 용량 부족 후 예약/현재 상태 불변, 정확한 여유에서 예약, 실제 HTTP 인증/엄격한 본문/no-store.
- 별도 현재 모델 검토: 원본 요구사항, 실제 diff/실행 결과, USER_SYNC→ENTITLEMENT→AGGREGATE→PIN_SLOT→문자열 정렬 RECORDING_ASSET 락 순서, MySQL pin trigger, 정책 버전/receipt 원자 rollback, 슬롯 중복·계정 격리, 기존 고정/파일·용량 보존, 기존 업로드 승인 연결 대조. 정렬 지적 해결 후 재검사 PASS. P13-08 승격/취소는 미착수.
- 변경: PinSlots/PinController, OpenAPI, 동일 H2/MySQL 공유 교체 검사 및 HTTP 검사. 도메인·HTTP 단계이며 후속 제품 화면 구현/실제 새 폰 실기를 통과했다고 주장하지 않는다. 이번 변경은 서버/계약 자동 검사 대상이라 추가 사용자 행동 없음.
- 학습: 고정 슬롯 하나에 두 파일 참조가 있어도 점유는 하나다. 그와 별개로 새 사본의 실제 용량은 기존 사본을 차감하기 전에 모두 확보해야 한다.
