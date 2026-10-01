# WORKFLOW-08 — 변경 영향에 따른 CI 최소 실행

2026-10-01 사용자 요청: 필요한 경우만 CI를 실행하고 지속 규칙으로 남긴다. 기존 앱 기능 완료 판정이나 테스트를 되돌리거나 삭제하지 않는다.

## 구현 및 근거

- `tools/ci-policy.json`이 workflow/job별 대상 경로의 단일 기준이다. 일반 문서는 제외, 자동화 도구는 Development, 앱은 Flutter, 서버/infra는 서버 및 DB, 공통 계약과 CI 정책은 통합 검증이다. 미분류는 전체를 기본으로 한다.
- 네 Actions의 push/PR 필터를 정책과 맞추고 `ci.yml`에 짧은 범위 판정 job을 추가했다. CI 내부에서도 앱만 변경하면 서버/DB 작업을 실행하지 않는다. 기존 검사 명령은 유지했다.
- `github-check.ps1 -BaseCommit`으로 push 전 기준부터 정확 HEAD까지 비교한다. 여러 커밋·삭제·이동을 포함한다. 명시 기준이 없으면 보수적으로 전체를 요구한다. 이전 정책 커밋은 기존 4개 CI 기준을 유지한다.
- 필요한 검사의 누락·skipped는 통과가 아니다. 불필요한 workflow는 NOT_APPLICABLE, 전체 제외는 NOT_REQUIRED다. ntfy에도 ‘CI 대상 없음(통과 판정 아님)’으로 구분한다. 실제 실패를 제외 처리로 숨기지 않는다.
- 보호 규칙은 변경하지 않았다. GitHub 경로 필터의 비교 한계/보호 규칙 때문에 필요한 검사가 없으면 대기하며 필요한 수동 workflow 실행으로 해결한다. 원본 정책 변경/보호 해제는 하지 않는다.

## 실제 검증

- PowerShell 7 `tools/tests/ci-scope.ps1`: 32 PASS. 문서·도구·앱·서버·계약·미분류·혼합 push, 필수 skipped 거부, 제외 근거 확인, 네 workflow push/PR 필터와 정책 일치.
- `tools/tests/workflow-gates.ps1`: 기존 97 PASS. `tools/tests/ci-notify.ps1`: 기존 12 PASS. HTTP 대역이며 실기 전송으로 계산하지 않는다.
- 모든 tools PowerShell 구문 검사 PASS. 기존 `.local/contract-venv/Scripts/python.exe`의 PyYAML로 네 workflow 파싱 PASS. 기본 Python에는 PyYAML이 없어 최초 파싱은 미실행됐고, 새 설치 없이 기존 가상환경으로 검증했다.
- 실제 과거 문서 커밋 범위 0133114→523a141을 push 이벤트로 대입한 ci-event-scope 결과: flutter=false/api=false/mysql=false. 새 파일/전송/개인 데이터 없는 로컬 이벤트 대역이다.
- 변경 판정 도구로 이전 커밋523a141 조회: legacy-all 기준 유지, API/멱등DB/Development PASS 및 CI PENDING을 실제 관측. 전체 통과로 확대하지 않는다.
- 현재 모델 직접 검토: 정책과 trigger 목록 일치, base 미확인 시 보수적 전체, 후속 알림의 NOT_REQUIRED 구분, 필요한 검사 skipped 금지, 기존 미커밋 P10-07 제외를 확인했다. 별도 에이전트 검수가 아니다.

## 남은 검증과 재개

이번에는 CI 선택·판정 도구 자체를 바꾸므로 전체 CI 한 번이 필요하다. 일반 push 뒤 정확 SHA와 push 전 원격 SHA를 기록하고 감시한다. 원격 적용은 아직 검증 대기이며 예상 제외 경로의 테스트를 실제 원격 실행 결과라고 기록하지 않는다. 사후 CI 결과 기록만을 위해 별도 전체 검증 커밋을 반복하지 않는다. 제품 재개 작업은 P10-02 의존 순서 전송의 최종 범위 대조다.
