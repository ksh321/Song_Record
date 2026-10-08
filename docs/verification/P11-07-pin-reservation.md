# P11-07 고정 슬롯 예약

- 사용자 승인: P11-08까지 원수, Astra/medium 현재 대화 직접 구현·검토. P11-06 최종 CI 후 별도 측정 구간 시작.
- 원본: 계획서 P11-07; 구현설계서 v1.11 원본 6.2(p00382~384), 정리 중 고정(p00436), 정책 버전(p00708~709), POST /pins(p00859~861).
- POST /v1/pins: recording_id와 entitlement_revision, 기존 구독 인증·기기 확인·멱등 키. USER_SYNC→ENTITLEMENT→RECORDING→PIN_SLOT→ASSET 순서로 예약한다.
- 한도는 user_entitlement의 기본 10을 사용한다. current 또는 pending이 있으면 1슬롯이며 대기도 포함. STORED는 current, 그 외는 pending; DELETING은 FILE_CLEANUP_IN_PROGRESS. 미연결 ACTIVE·SAVED도 가능.
- 동일 녹음의 새 요청은 기존 슬롯을 반환하며 원래 op 재전송은 원래 응답을 보존한다. 한도·정리·계정·상태 오류는 슬롯과 receipt를 남기지 않는다. 파일 전송·바이트 예약은 후속 작업으로 분리한다.
- 연결 검토 보완: 원본 p00708에 따라 고정·자동 역할·재연결 시 기존 RecordingAsset.cloud_revision을 증가시킨다. 오래된 cleanup 버전 차단용이며 물리 상태·파일·용량은 바꾸지 않는다. P11-05/06 선정 결과·작업 완료 이력은 유지한다. 기존 자산이 없는 후보는 그대로 선정 가능하다.
- 검증: 서버 전체 테스트로 회귀를 확인한 뒤 실패한 임시 fixture(ACTIVE 기본값, H2 ALTER 문법), 신규 컨트롤러 계약 등록, 정책 버전 기대값을 수정했다. 영향 검사 Retention/PinSlots/RecordingMetadataBoundary/RecordingLinking/ApiContract 전체 통과 (`affected-check.log`). STORED+pending 혼합 9→10 경쟁 공통 시나리오 보강 후 PinSlots 5개 재통과 (`pin-check.log`).
- 계약 검사: 기존 contract-venv-modern으로 OpenAPI·참조·보안·wire 예제 7개·경계 141개 PASS. 신규 경로는 서버 HTTP 검사와 일치 확인.
- 검토: 현재 모델이 원본 완료 조건·diff·실행 결과를 별도 대조. 중복 슬롯, stale entitlement, 타 계정·DRAFT·TRASHED·DELETING, version overflow rollback, 자산 상태/바이트 보존 확인. 실제 MySQL 동일 동시성 시나리오는 필수 CI에 연결.
- 서버 API 범위로 현재 폰 실기 불필요. 필수 CI 통과 전 완료 아님.
- 학습: 고정 슬롯 수와 실제 서버 파일 바이트는 서로 다른 자원이다. 업로드를 기다리는 동안에도 슬롯은 예약하지만 파일을 복사하거나 바이트를 중복 계산하지 않는다.
