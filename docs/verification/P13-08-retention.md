# P13-08 고정 교체 확정·취소 (원수)

- 원본 계획 P13-08, 설계 고정 교체 및 API 교체 취소, R063/V12 대조. 사용자 지정 gpt-6.1-sol/medium 고정, 현재 모델 직접 구현·별도 검토.
- 검증 완료 STORED 확정과 동일 트랜잭션으로 pending을 current로 승격한다. 이미 STORED인 대상은 교체 요청에서 즉시 확정하며 주기 처리에서도 이전 대기를 복구한다. 기존 파일·다른 자동 보관 사유·used를 삭제하지 않는다.
- POST /v1/pins/{slotNo}/replacement/cancel은 인증·슬롯 버전·receipt를 확인해 pending만 해제한다. 업로드 실패·만료·취소는 최초 승인 때 캡처한 operation_id가 일치하는 교체만 해제한다. 같은 녹음의 후속 요청을 과거 실패가 취소하지 않는다. V19는 캡처 ID 변경을 금지하고 과거 NULL은 임의 해제하지 않는다.
- 변경: PinTransitions, PinSlots/Controller/Scheduling, UploadApproval/Reservations/Finalization/Recovery, V19, OpenAPI 및 H2/MySQL 공유·HTTP 검사.
- 로컬 전체 서버 test/bootJar PASS 68초. 최종 복구 추가·캡처 고정 영향 15검사 PASS 28초. API 계약 검사 PASS 141 경계 사례. 실제 MySQL 환경은 로컬에서 실행 불가이므로 CI 일회용 MySQL 필수. 실행 옵션 오류는 검사 실행 전 바로잡았다. 추가 복구 시험은 없는 asset을 UPDATE한 준비 자료를 INSERT로 보완 후 통과; 제품 실패 횟수와 구분한다.
- 검사: 검증→확정 원자성·재전송·STORED 즉시/주기 복구, 명시 취소, 실패 복구, 과거 업로드 실패와 새 요청 분리, 확정/취소 동시 요청, 버전 한계 전체 rollback, 기존 파일·자동 사유·회계 보존, HTTP 인증/no-store/엄격 본문.
- 별도 현재 모델 검토: 원본 완료 조건·실제 diff·실행 결과, USER_SYNC/PIN_SLOT/문자열 순서 ASSET 잠금, 업로드 lease·policy 버전·캡처 ID, receipt/회계/이벤트 동일 TX, V19 불변 트리거·기존 NULL 호환, 취소 후 늦은 확정 거절 대조. 지적한 복구 준비 자료를 수정하고 재검증 완료.
- 서버 도메인·HTTP 변경이며 제품 UI/새 폰 실기를 통과했다고 주장하지 않는다. P13-03 실제 파일 보존 6개 통과 근거 유지. 추가 사용자 조작 없음. 최종 SHA 필수 CI 대기.
- 학습: 교체 대기는 새 파일이 확정될 때까지 기존 고정을 보호하며, 실패는 그 요청의 대기만 해제한다. 파일 UUID만 같다고 과거 요청이 최신 대기를 지울 권한을 갖지 않는다.

- 최초 실제 MySQL CI에서 current가 남은 슬롯의 operation_id/requested_at을 제거해 V5 ck_pin_request 위반 확인. 전환·취소 후 현재 고정 요청 이력을 보존하고 H2에 동일 CHECK를 추가했다. 별도 기존 V9→최신 마이그레이션 개수 기대값은 V19 추가에 맞춰 9→10 갱신. 서로 다른 원인 각각 최초 수정이며 제약 약화 없이 영향 재검사 및 최종 CI 확인.

- 요청 이력 유지 + 동일 H2 제약 추가 후 영향 검사/bootJar PASS20초. 실제 V5 CHECK와 요청 이력·새 요청 덮어쓰기·V19 캡처 불변의 별도 현재 모델 재검토 완료. 최종 SHA 전체 범위 CI 대기.

- 수정본 실제 MySQL 공유 동작 검사 PASS. 별도 shell 업그레이드 검사는 V19 성공 적용 목록을 V18까지의 고정 문자열과 비교해 실패; 같은 버전 검사 기준 갱신의 누락 위치를 V19까지 맞췄다. 데이터/키 보존·재시작 checksum 검사 유지. 최종 SHA 전체 CI 재확인.
