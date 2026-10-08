# P11-08 고정 해제와 보관 조회

- 승인: P11-08까지 원수, Astra/medium 현재 대화에서 연속 수행. P11-07 최종 SHA CI 통과 후 자동 측정 구간 시작.
- 원본/요구: 계획서 P11-08, 구현설계서 6.2·7.4·12.4(DELETE /pins/{slotNo}, GET /recordings/{id}/retention, GET /storage), R058·R065·R066. 교체 pending만 취소하는 P13-08은 이 작업에 포함하지 않는다.
- 해제: 계정·entitlement·slot 잠금 아래 base_revision을 확인하고 current/pending을 비운다. 빈 행과 버전은 유지해 슬롯 재사용 후 과거 요청이 새 고정을 해제하지 못하게 한다. 기존 멱등 응답을 재사용하고 자산 정책 버전을 함께 증가시킨다.
- 보존: 파일·자산 상태·용량·자동 역할·cloud_hold를 삭제하지 않는다. 고정만 해제된 사본도 후속 P13의 안전 정리 절차 전까지 그대로 둔다.
- 조회: 계정별 REPEATABLE_READ 안에서 일관되게 읽는다. 자동 역할·고정 슬롯·보존 사유와 실제 서버 파일 상태를 구분하며 로컬 기기 파일 유무는 추정하지 않는다. object_key는 반환하지 않는다.
- 용량: used/reserved는 기존 사용량 장부, 실제 파일 수는 자산별, 슬롯은 점유 행별로 집계한다. trash/cleanup/hold 바이트는 겹칠 수 있는 used의 부분집합이다. hold의 중복 참조는 EXISTS로 한 번만 합산한다. ORPHAN_KEEP만으로 정리 가능하다고 표시하지 않는다.
- 로컬: 서버 전체 543개 중 475 PASS, 67 환경 조건 skip, 1 테스트 seed의 곡 ACTIVE 기본값 누락 확인. 공유 seed를 명시적으로 보완하고 Pin/Retention/ApiContract 영향 검사 30개 모두 PASS(실패·skip 0). 로그 `.local/workflow/p11-08/local-check.log`, `affected-check.log`, `affected-counts.json`.
- API 계약: OpenAPI·참조·보안·기존 wire 7개·경계 141개 PASS. 신규 해제/조회 HTTP 응답, no-store, 인증·계정 격리 확인. 실제 MySQL에도 같은 파일 다중 보호/중복 집계/슬롯 재사용/과거 요청 재생 시나리오 연결.
- 현재 모델 별도 검토: 요구사항·diff·테스트 결과 대조. 단일 파일 3역할+고정+2hold, 취소 후 파일 보존, 재사용 슬롯 stale revision, 자산 버전 overflow rollback, 타 계정 읽기·삭제 차단, DELETING 잔여 바이트 확인.
- 서버 API 범위로 사용자 폰 실기 불필요. 필수 CI 통과 전 완료 아님. 승인 종료는 P11-08이며 P11-09 미착수.
- 학습: 보호 사유를 해제하는 것과 물리 파일을 삭제하는 것은 별도 단계다. 중복 보호는 바이트를 늘리지 않으며, 오래된 요청은 버전과 멱등 응답으로 새 상태에 영향을 주지 못하게 한다.
