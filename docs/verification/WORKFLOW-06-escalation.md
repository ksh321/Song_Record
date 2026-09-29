# WORKFLOW-06 — 최대 추론 추가 해결 단계

2026-09-29 최신 사용자 지시를 기존 AGENTS.md·개발 워크플로우에 통합했다. 기존 3회 실패 즉시 사용자 대기 규칙을 대체한다.

- 같은 문제의 원인 분석·수정 시도 3회 실패 후 사용자 응답을 기다리지 않고 Astra의 실제 지원 최대 추론으로 추가 최대 3회 해결한다.
- 누적 실패와 최대 추론 실패를 따로 기록한다. 이미 최대 추론에서 3회 실패했으면 추가 반복하지 않는다. 환경 오류는 이 해결 예산과 구분한다.
- `tools/workflow-common.ps1`의 `Get-AgentRunPlan`, `tools/run-agent.ps1`이 이 선택/중단 조건을 적용한다. 마스터가 문제 ID별 실제 기록을 입력하며 단순 명령 실행 횟수를 실패 시도 수로 사용하지 않는다.
- `tools/phone-notify.ps1` Escalation 알림은 작업 ID, 상향 전후 모델/추론, 열거형 실패 요약·판단 요청을 담는다. 임의 로그·비밀값·개인 자료는 받지 않는다. 자세한 조치는 대화/진행 문서에 남긴다.

## 설정과 관측

로컬 공식 모델 지원 목록에서 gpt-6-astra의 low/medium/high/xhigh/max/ultra를 확인했다. 현재 지원 최대는 ultra다. P10-03b 추가 시도 1 작업자 실행 헤더에서 `model: gpt-6-astra`, `reasoning effort: ultra`를 확인했다. 요청은 service_tier=default, features.fast_mode=false이며 실제 서버 처리 tier는 미확인이다. 마스터 자신의 모델을 변경했다는 뜻은 아니다.

## 검증

`pwsh -NoProfile -File tools/tests/workflow-gates.ps1`: 종료 0, 47 검증 통과. 상향 전/후 예산, 이미 최대 3실패, 잘못된 카운터, 환경 오류, 알림 내용과 서버 접수/실수신 구분을 포함한다. HTTP는 격리된 파일과 메모리 stub이므로 이 테스트는 사용자 폰에 알림을 보내지 않았다.

첫 확장 테스트에서는 이전 네트워크 실패 시나리오의 모의 실패 플래그를 그대로 둬 새 성공 시나리오가 실패했다. fixture를 성공 상태로 전환한 뒤 위 47개가 통과했다. 제품 스케줄러 실패 횟수에 합산하지 않는다. 기존 검사를 삭제하거나 완화하지 않았다.

별도 Sol/high 검수의 API/구독 혼합 로그인 판정, UNKNOWN 알림 재전송 지적을 보완했다. API 표시를 우선 거부하고 runner가 공통 판정을 사용한다. 같은 task/kind의 UNKNOWN 전송은 60초 뒤에도 자동 재전송하지 않고 대화에서 상태 확인 대상으로 남긴다.
보완 후 같은 검증 명령 종료 0, **50 검증 통과**. 최종 별도 검수에서 이전 두 지적 해결·추가 결함 없음. 일반 규칙/스크립트 검수는 복잡한 제어 로직 수준으로 배정했으며, P10-03b 해결 작업자/후속 검수와 분리한다. 커밋·해당 SHA CI는 아래 후속 기록으로 확인한다.

## 현재 적용 대상

P10-03b-SCHEDULER: 종전 Astra/high 1차, Astra/xhigh 2·3차 실패를 유지하고 Astra/ultra 추가 3회 검수까지 수행했다. 최대 수준 실패 3회에서 실제로 해당 작업을 중단하고 ntfy Escalation을 보냈다(서버 접수, 실수신 미확인). 이전보다 더 시도하도록 임의로 카운터를 초기화하지 않았다. USB/로그인 빌드 설정·새 실기는 별도 대기다. 상세는 [P10-03b](P10-03b-sync-ui.md), 최신 상태는 [progress](../progress.md)를 따른다.

운영 변경 커밋 `9105beeb16e4f374348dd5adefcbfe2feb559450` 일반 푸시 완료. 해당 SHA CI 36564321988 / API contract 36564321983 / Idempotency MySQL 36564322119 / Development workflow 36564322001 모두 success. 후속 AuthFollowup 고정 알림 문구와 이 결과 기록은 별도 문서/알림 변경이다.

이후 사용자가 P10-03b 수동 보완을 직접 실행하고 별도 검수를 명시 요청했다. runner에 Reviewer만 허용하는 `ReviewAfterUserFix`를 추가해 누적 6/최대 3을 그대로 남기고 Astra/ultra 검수를 수행했다. 자동 Worker 예산을 추가하거나 초기화하지 않았다. `tools/tests/workflow-gates.ps1` 최신 종료 0, 52 검증 통과(최대 실패 후 명시적 사용자 수정 검수 허용 및 Worker 거부 포함).
