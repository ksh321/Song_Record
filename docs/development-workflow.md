# 개발 자동화 실행 안내

Codex가 현재 작업에서 명령과 로그 확인을 직접 수행하는 흐름이다. 상시 자율 데몬이나
유료 API 기반 봇을 설치하지 않는다. 다음 대화는 루트 AGENTS.md와 progress.md에서 이어간다.
2026-09-29부터 남은 구현을 의존 순서대로 연속 진행한다. 단계 보고 뒤 매번 “다음”이나
승인을 기다리지 않는다. 기존 설정을 재구축하지 않으며 지원이 확인되지 않은 세션 자동 재시작은 약속하지 않는다.
초기 구성 결과와 제한은 [검증 기록](verification/WORKFLOW-01-bootstrap.md)을 따른다.

## 실행 입구

사용자 개입은 루트 [내가할일.md](../내가할일.md)에서 관리한다. 상태는 확인 필요 → 사용자 결과 전달됨 → AI 검증 중 → 완료이며, 요청 취소는 사유를 남긴다. 상단 건수는 미종료 세 상태의 합이다. 완료 항목은 하단 기록으로 옮긴다. USB 연결 응답을 앱 실기 통과로 확대하지 않는다.

새 요청은 ID·시각·이유·정확한 앱 커밋/설치 준비 상태·준비·순서·기대 결과·회신 양식을 먼저 기록한다. 그 뒤 `tools/phone-notify.ps1 -Mode Send -TaskId P10-03b -Kind Intervention -ItemId USER-001 -Revision 1 -Action LoginSetup` 형태로 고정 행동 문구만 전송한다. 이 명령은 형식 예시이며 현재 USER-001은 이미 알린 요청이므로 재전송하지 않는다. 동일 ID/판본의 성공 또는 불확실 전송은 재발송하지 않는다. 앱/절차 변경은 같은 항목의 판본과 변경 이유를 갱신하고 한 번 알린다. 알림 서버 접수는 실제 수신/실기 통과가 아니다. 진행·종료 보고에는 미종료 건수와 파일 링크를 표시한다.

저장소 루트에서 PowerShell 7로 실행한다. 명령 실행은 AI가 담당하며 로그인·USB 승인·청취만
필요 시 사용자에게 요청한다. 결과 0=해당 자동 검사 통과, 1=실패, 2=미확인/대기다.
명령이 통과해도 수동 검증을 포함한 전체 기능이 완료됐다는 뜻은 아니다.
명시적인 사용자 검증 완료 확인도 완료 근거다. [2026-09-29 사용자 확인](progress.md#user-acceptance-20260929)
범위의 기존 기능은 검증 완료로 유지하고, 과거 문서 부족만으로 실기를 다시 요청하지 않는다.
이후 변경은 변경 부분과 영향 범위만 근거에 맞게 검증한다. 현재 PC 실행 환경 상태는 별도 관리한다.

```powershell
pwsh -NoProfile -File tools/workflow.ps1 -Mode Doctor -SourcePath 'C:\Users\shoon111111\Desktop\source'
pwsh -NoProfile -File tools/workflow.ps1 -Mode Quick
pwsh -NoProfile -File tools/workflow.ps1 -Mode Mobile
pwsh -NoProfile -File tools/workflow.ps1 -Mode Api
pwsh -NoProfile -File tools/workflow.ps1 -Mode Phone
pwsh -NoProfile -File tools/github-check.ps1 -Commit <40자리SHA> -InspectPolicy -Account ksh321
```

- Doctor: 도구·버전·Docker 엔진·구독 로그인·기기·외부 원본 대응 확인. 설치/업그레이드/DB 시작 안 함.
- Quick: 원본/색인 정합성, 자동화 실패 경로 테스트, 변경 공백 오류 확인.
- Mobile: 기존 Flutter 분석과 P10 동기화 관련 테스트만 실행. 의존성 준비는
  `apps/mobile`에서 `flutter pub get --enforce-lockfile`. 잠금 파일을 바꾸는 upgrade는 하지 않는다.
  이후 작업은 범위에 맞는 테스트를 선정하고 명령을 검증 문서에 기록한다.
- Api: 서버 기존 테스트를 offline으로 실행. 캐시에 의존성이 없으면 실패를 기록한 뒤
  필요한 다운로드만 별도 실행한다. DB 생성/삭제·migration 실행을 대신하지 않는다.
- Phone: USB 연결 기기 점검. 현재 runner는 USB 한 대만 연결한 상태를 지원하며 `-DeviceId`로
  해당 기기 일치를 확인할 수 있다. 여러 USB 기기는 대기로 남긴다. 서버가 준비된 후 `-Reverse`로
  휴대폰 localhost:8080을 개발 PC로 연결할 수 있다. 앱 설치/데이터 초기화는 하지 않는다.
  새 변경에 필요한 녹음·청취·로그인 실기는 변경 영향에 맞게 선정한다. 과거 체크리스트의
  대기 문구만으로 사용자 확인이 끝난 기존 기능의 실기를 반복하지 않는다.

raw 로그·프롬프트·기계별 JSON은 `.local/workflow`에 저장하고 Git에서 제외한다.
워크플로우 실행별 로그는 runs의 고유 폴더에 보존하고 mode별 JSON은 최신 결과를 가리킨다.
JSON에는 기준 HEAD, 시작/종료 미커밋 변경, working_tree 범위, 전체 판정과 실행 예외를 남긴다.
Doctor와 Quick 결과는 독립적이다. Docker가 꺼졌어도 문서/로컬 동기화 검증은 진행할 수 있다.

## 자료와 변경 계약

[원본/색인 manifest](reference/search/manifest.json), [231개 작업 색인](reference/search/tasks.json),
[설계 검색본](reference/search/design.txt), [계획 검색본](reference/search/plan.txt)을 사용한다.
검색본은 원본을 대체하지 않는다. Word 문단 번호·원본 경로·해시로 출처를 찾는다.
원본 6개는 이미 저장소에 있어 다시 복사하지 않았다. 텍스트 해시는 CRLF를 LF로 정규화하며
DOCX는 원본 바이트 해시다. 외부 원본의 실제 바이트 해시는 초기 검증 기록에 보존한다.

```powershell
python tools/index_sources.py --source <실제source경로>
python tools/index_sources.py --check --source <실제source경로>
```

실제 내용이나 스크립트의 승인된 해시와 다르면 실패하며 덮어쓰지 않는다. 변경 승인 후 원본/기준을 별도로 갱신하고
색인을 다시 생성한다. CI는 저장소 원본으로 재생성 결과를 대조하므로 개인 source 경로가 필요 없다.
D12의 기간별 차트 변경과 기존 탭 재선택 계약은 범위가 명확한 후속 결정이다.
D06과 P09-07b 컨디션 충돌은 승인 근거 확인 전 임의로 어느 한쪽을 삭제하지 않는다.

## 에이전트와 속도

마스터가 변경 대상과 파일 소유권을 배정한다. 작업자는 분석/구현안을 만들고 별도 검수자는
완성 diff와 테스트 증거를 검토한다. 현재 Windows의 중첩 읽기 제한 때문에 runner는
입력 자료만 분석하고 마스터가 파일 변경·명령 실행을 수행한다.

```powershell
pwsh -NoProfile -File tools/run-agent.ps1 -Role Worker -Risk Explore -PromptFile .local/workflow/worker-input.txt
pwsh -NoProfile -File tools/run-agent.ps1 -Role Reviewer -Risk Complex -PromptFile .local/workflow/review-input.txt
```

위 예는 Luna/medium 탐색과 Sol/high 검수다. Sensitive는 Astra/high, Escalation은 Astra/xhigh.
원인 분석·수정을 포함한 동일 문제 실패 3회부터는 사용자 응답을 기다리지 않고 Astra의 지원 최대
추론으로 추가 최대 3회 해결을 시도한다. 현재 모델 지원 목록에서 ultra를 확인했다.
`-SameProblemFailures 3 -MaximumReasoningFailures 0`은 Astra/ultra를 요청한다.
누적 4회 중 ultra 실패 1회면 각각 4/1, 누적 5회 중 2회면 5/2를 전달한다.
최대 수준 실패가 3이면 누적 횟수와 무관하게 호출을 거절한다. 이미 ultra로 시작해 3회 실패한
경우도 3/3으로 종료한다. 문제 ID의 실제 기록을 입력하며 모델/세션 변경으로 초기화하지 않는다.
중단 후 사용자 직접 수정 확인과 명시적 검수 요청이 있으면 Reviewer에만 `-ReviewAfterUserFix`를
전달한다. 기존 누적/최대 실패 수는 그대로 입력한다. 이 예외는 자동 Worker 재시작 권한이 아니다.
실제 모델 지원 실패 시 유료 API로 우회하지 않는다. `--strict-config`로 설정 이름을 검사하고
ChatGPT 로그인, `service_tier=default`, `features.fast_mode=false`를 요청한다.
기록 JSON은 **요청 설정**이다. CLI 헤더가 모델/추론을 확인해도 서버의 실제 처리 속도는
현재 노출되지 않아 미확인이다. 마스터 현재 세션의 모델/속도를 이 스크립트로 바꾸지 못한다.
앱에서 Standard 및 Fast 끔을 확인해야 한다.
[공식 속도 문서](https://learn.chatgpt.com/docs/agent-configuration/speed)와
[설정 참조](https://learn.chatgpt.com/docs/config-file/config-reference)를 기준으로 확인했다.

## 커밋 푸시 CI

GitHub CLI는 설치되어 있지 않아 기존 Git Credential Manager와 GitHub REST 조회를 사용한다.
추가 API 결제는 없다. 로그인 토큰은 메모리에서만 쓰며 API 읽기 실패는 통과로 처리하지 않는다.
현재 계정이 여러 개이므로 runner는 저장소 소유자의 기존 계정을 선택하거나 `-Account`를 받는다.

마스터는 `git diff`/테스트/별도 검수 후 **이번 파일 경로만** add하고 staged diff를 다시 확인한다.
일반 `git commit`과 `git push origin HEAD:<대상브랜치>`는 승인 범위다. 서버 보호가 거절하면
강제 푸시하지 않고 브랜치/PR 경로를 사용한다. rules/protection 조회 실패도 그대로 기록한다.

정확한 새 SHA에 CI, API contract, Idempotency MySQL, Development workflow 네 workflow가
실제 파일 경로로 대응하고 필수 job이 모두 있어야 한다. API 목록은 페이지 끝까지 확인한다.
각 run의 job도 success여야 하며 skipped/cancelled/missing은 통과가 아니다.
`-InspectPolicy`를 요청했는데 정책 조회가 실패하면 CI가 모두 성공해도 전체는 대기(exit 2)다.
CI 자체의 성공과 서버 보호 규칙을 모두 만족했는지는 구분한다.
기존 main만 push CI가 작동하므로 기능 브랜치는 PR 이벤트 또는 승인된 workflow_dispatch가 필요하다.
`github-check.ps1`은 단발 조회다. AI가 30~60초 간격으로 실행하고 사용자에게 진행 상태를 알린다.
나중의 새 커밋은 이전 커밋 CI 결과로 완료 처리하지 않는다.

## 재개와 학습 기록

재개 시 Git 상태/원격/코드/진행 기록과 실행 중 프로세스를 확인한다. 작업별 구현→관련 테스트→
별도 검수(원본·실제 diff·실행 결과 대조)→필요 통합→커밋/푸시→정확한 SHA 필수 CI→기록 갱신을
완료하면 다음 작업을 선정한다. 난이도·위험도에 따른 모델 기준은 AGENTS.md를 따른다.
마스터는 Astra/medium 기본이며 속도 요청과 관측을 구분하고 미노출 속도 탐색은 반복하지 않는다.

progress의 현재 작업 표에는 상태/검증/대기 사유/사용자 요청/다음을 남긴다. 실패는 문제 ID로
누적하며 최대 추론 실패 횟수도 따로 남긴다. 기존 모델 3회 실패는 자동 상향 지점이고 최대 수준
3회 실패는 해당 작업 중단·ntfy 알림 지점이다. 모델·추론·원인·수정 방법·검증 결과를 기록한다.
분석/수정 없는 동일 명령 반복은 추가 해결 시도로 세지 않는다. 권한·네트워크·도구 부재는 별도
환경 문제로 관리하며 모델 상향으로 해결했다고 하지 않는다. 기존 ENV-GRADLE-LOOPBACK 환경 실패 3회는 유지한다.
중단을 감지할 수 있으면 미커밋 변경·실행 중 프로세스·남은 검증·재개 명령을 추가한다.

폰 조작/청취/테스트, 미승인 정책 선택, 로그인/기기/권한, 최대 추론 3회 실패, 별도 승인이 필요하면
해당 작업만 사용자 응답 대기로 두고 ntfy를 보낸다. 이유/절차/기대 결과/답할 내용을 대화에 적는다.
구체적 결과나 정책 선택은 해당 조건과 대응시켜 재개하고, 결과 없는 “이어서 진행”을 통과로
기록하지 않는다. 무관하고 파일 충돌 없는 작업은 계속하며 모든 진행 가능한 작업이 막힐 때만 전체 대기한다.

작업별 verification 문서에 작업/요구사항 ID, 선행 조건, 변경 파일, 명령·종료코드·실제 결과,
대상 SHA, 검수 지적과 해결, 수동 대기, 다음 ID를 적고 progress.md 최신 절을 갱신한다.
최대 추론 3회 실패/구독 한도 시 실패 시도와 재개 명령을 남긴다. 상태를 숨기거나 테스트를 약화하지 않는다.

핵심 학습 개념은 트랜잭션과 멱등성이다. 현재 P10 코드는 로컬 입력과 전송 큐를 함께 저장해
부분 저장을 막고, op_id로 같은 작업 재시도를 식별한다. 큐 후보 판정과 실제 서버 승인 반영을
분리했기 때문에 P10-02a 테스트가 성공해도 양방향 동기화 완료는 아니다.

## 후속 점검과 휴대폰 알림

[WORKFLOW-02](verification/WORKFLOW-02-followup.md)에 Docker/USB, 보호 API 제한, 모델 실행과
D06/P06 선행 조건을 기록한다. 모델 runner의 `-Finding RequirementsMissing|LogicError|ReviewBlocker`
는 위험 수준을 상향하고 `EnvironmentOnly`는 유지한다. 논리 문제 누적 3회는 위 최대 추론 단계로 전환한다.
실제 모델/추론 실행을 확인하지 못하면 변경됐다고 보고하지 않고 필요한 설정을 휴대폰에 알린다.

`tools/phone-notify.ps1`은 무료 ntfy에 작업 ID와 고정 문구만 보낸다.
처음 Init → Android 앱 설치/알림 허용 → Subscribe(USB) → Send(Trial) → 사용자 실제 수신 답변 → Confirm.
사람의 실기가 필요하면 대화에 이유/순서/기대 결과를 먼저 남기고
해당 작업 ID와 문서에 먼저 등록한 `-ItemId USER-NNN -Revision N -Action PhoneSteps`를 지정해 `-Kind PhoneTest`로 실행한다. 과거 P06 실기를 다시 요청하는 예시가 아니다.
사람 개입 요청은 `-Kind Intervention`이며 기록된 항목 ID가 필수다. 푸시 실패 시 대화로 알리고 실기는 계속 대기다.
최대 추론 실패/설정 개입은 `-Kind Escalation -BeforeModel Astra -BeforeReasoning high/xhigh
-AfterReasoning ultra -FailureCode SchedulerRecovery`로 작업 ID와 상향 전후 모델·추론, 안전한 실패 요약·
판단 요청을 보낸다. 모델 실행 미확인은 AfterReasoning=unconfirmed, FailureCode=ModelUnavailable이다.
열거형 고정 문구만 허용해 로그·키·개인 정보를 알림에 넣지 않는다. 필요한 구체 조치/상세 시도는 대화와 문서에 적는다.
무작위 topic/config는 `.local` 밖으로 복사하지 않는다. 이 스크립트는 예약 실행 서비스가 아니며
활성 작업 중 마스터가 필요한 시점에 호출한다. 구독 한도 뒤 몰래 API로 계속 실행하지 않는다.

## 조건부 리셋권 1회 허용 — 2026-09-29

최신 사용자 지시는 실제 사용량 한도 도달 시 보유 리셋권 중 아무 1개를 자동 사용하는 것을 총 1회 허용한다.
이전 “이번 주 만료권만” 제한은 대체됐다. 특정 권을 고를 수 없는 공식 도구로도 이 허용 범위는 실행 가능하다.
추가 리셋권·유료 결제는 금지다. 아직 사용하지 않았다. 마지막 공식 조회 당시 주간 67% 사용/33% 남음, 일반 사용 가능.

1. 실제 공식 한도 오류 또는 새 get_usage_limits의 사용 제한 상태와 해당 창 사용량을 확인한다. 90% 사용만으로 선사용하지 않는다.
2. 사용 가능한 권과 이번 허용의 미사용 상태를 확인하고 `.local/workflow/usage-reset-authorization.json`에 저장한 단일 시도 키로 consume_usage_reset을 호출한다.
3. reset/alreadyRedeemed는 1회 사용 완료다. 불확실한 응답은 같은 키로만 확인하며 두 번째 권은 사용하지 않는다.
4. 공식 사용량을 재조회해 한도 갱신을 확인한다. 실행 결과와 사용량 조회는 별도 증거로 기록한다. 재조회 실패가 추가 사용을 허용하지 않는다.
5. 진행할 수 있으면 이어서 작업한다. 한도 부족으로 진행 불가하면 가능한 시점에 SHA·미커밋·프로세스·남은 검증·재개 지점을 저장하고 기존 ntfy의 작업 ID/Intervention 알림을 보낸다.

도구 자체의 실행 조건은 5시간 또는 주간 잔여 10% 이하이지만 사용자 허용은 실제 한도 도달 때다. 누락 정보는 도달로 추정하지 않는다.
세션이 이미 중단된 뒤 자동 재시작·알림 실행을 보장하지 않는다. 공식 일반 안내는 [사용량과 리셋 안내](https://learn.chatgpt.com/docs/pricing), 계정별 실제 상태는 공식 앱 도구 응답으로 확인한다.
