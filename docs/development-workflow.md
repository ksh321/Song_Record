# 개발 자동화 실행 안내

Codex가 현재 작업에서 명령과 로그 확인을 직접 수행하는 흐름이다. 상시 자율 데몬이나
유료 API 기반 봇을 설치하지 않는다. 다음 대화는 루트 AGENTS.md와 progress.md에서 이어간다.
초기 구성 결과와 제한은 [검증 기록](verification/WORKFLOW-01-bootstrap.md)을 따른다.

## 실행 입구

저장소 루트에서 PowerShell 7로 실행한다. 명령 실행은 AI가 담당하며 로그인·USB 승인·청취만
필요 시 사용자에게 요청한다. 결과 0=해당 자동 검사 통과, 1=실패, 2=미확인/대기다.
명령이 통과해도 수동 검증을 포함한 전체 기능이 완료됐다는 뜻은 아니다.

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
  녹음·청취·로그인 실기는 관련 작업 문서의 체크리스트로 검증한다.

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

작업별 verification 문서에 작업/요구사항 ID, 선행 조건, 변경 파일, 명령·종료코드·실제 결과,
대상 SHA, 검수 지적과 해결, 수동 대기, 다음 ID를 적고 progress.md 최신 절을 갱신한다.
3회 실패/구독 한도 시 실패 시도와 재개 명령을 남긴다. 상태를 숨기거나 테스트를 약화하지 않는다.

핵심 학습 개념은 트랜잭션과 멱등성이다. 현재 P10 코드는 로컬 입력과 전송 큐를 함께 저장해
부분 저장을 막고, op_id로 같은 작업 재시도를 식별한다. 큐 후보 판정과 실제 서버 승인 반영을
분리했기 때문에 P10-02a 테스트가 성공해도 양방향 동기화 완료는 아니다.
