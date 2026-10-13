# P24-04 — 관측과 감사 기록

## 원본과 범위

- 계획 p01044~p01046, 설계 p01100~p01122, R120/R124. [운영 절차와 지표 해석](../runbooks/operations-observation.md).
- V29 operations_observation, OperationsContext/Filter/Recorder/Metrics/Operator. API 세션에서 UUID만 전달, 고정 대상·녹음 저장·동기화 미수신 변화량 계측. 요청/본문/토큰/원음/메모/검색어/서명 URL/작업 payload 미전달.
- JobQueue/JobConfiguration: 실제 커밋 뒤 작업자 UUID·job/대상 UUID·시도와 lease 수명. 롤백의 성공 감사 없음. pin_slot/deletion_ledger DB 트리거: 확정 교체/영구 삭제의 권한 소유자·전후 UUID·시각·결과를 변경과 함께 보관. 고정10 점유·대기와 보관 완료 구분.
- 검증용 비공개 집계/60초 감시와 로그 제한. RequestIdFilter는 기존 공개 request ID 응답을 유지하고 로그 상관값만 SHA-256로 변경, 비표준 HTTP method 원문 제외.
- 서버 관측만 측정한 것을 전체 활성 계정/실제 재생/오프라인 방문으로 주장하지 않는다. R124 전체 앱 신호 및 수요 검증은 P25-07 범위에 남긴다. 실제 재생은 null/NOT_CONNECTED, URL 발급은 별도다. 관측 행 보관/운영 알림 최종 대조는 P24-09/10에서 이어간다.

## 실행과 검토

- 서버 전체 `gradlew.bat build --offline` PASS(1분20초). 추가 동기화/저장/작업/관측 영향61개, 실패0/오류0/skipped7. 전체 실행의 개수를 추정/합산하지 않는다. 이후 보완한 동일 기간 고정/제출 수요와 로그 비밀값 경계는 관련 영향 검사·bootJar로 확인한다.
- 도구 검증 재개5개·운영 감시2개 PASS. 로그 원문을 저장하지 않고 실패 표식만 계산, 잘린 결과를0으로 보지 않는 것을 검사한다.
- 현재 모델 별도 검토: 원본 완료 조건·actual diff·계정 격리/데이터 보존·원자적 감사·작업 rollback/lease·재시도 중복·로그 누출·관측 미확인 범위 대조. 사용자 고정 6.1 Sol/medium, 별도 에이전트/모델 호출 없음.
- 실제 p24-04-local/API·worker/V29 기동, HTTPS 건강과 보호 경계200/404/401/가짜 인증503 PASS. 보호 요청의 고정 결과·처리 시간 생성, 비공개 MySQL 집계 조회와 관측 쓰기 실패0 확인. 실제 정상 사용자/재생/오프라인 지표를 시험했다고 주장하지 않는다.
- MySQL 전체 마이그레이션에서 확정 교체/원장 트리거·rollback·고정10·작업 커밋 감사 검사는 이 번호의 필수 MySQL CI에서 실행한다. 로컬 H2로 MySQL 트리거 통과를 대신하지 않는다.

## 남은 단계

최종 이미지·개인정보 보완·현재 소스 검토 후 커밋/푸시·해당 SHA 필수 CI를 확인한다. 다음 P24-05, 승인 끝 P24-10.

- 최종 정상 삭제 대기/작업/관측 영향21개 실패0·오류0·skipped0 PASS, 요청 ID/관측 개인정보 영향 PASS. MySQL 합성 고정 fixture를 기존1기반 슬롯·SAVED STORED·operation/requested_at 제약에 맞춰 검토했다(검사 기대값 완화 없음). 실제 source migration을 이미 적용한 뒤 내용은 변경하지 않았다. 대상 SHA 필수 MySQL에서 실제 원자성·트리거를 확인한다.
