# WORKFLOW-02 — 초기 설정 후속 점검

2026-09-29. 시작 SHA `c5161fab04538c0fe2e27ddeb6af87a481b4fe43`, main, 사용자 미커밋 변경 없음.
제품 기준 `9b2fc86` P10-02a. 이번에는 제품 코드·원본 자료·DB 스키마를 변경하지 않는다.
요구사항: 사용자 후속 요청 1~7, D06/R029/X05, P06-06/07/08 계정 격리, P10 선행 조건.

## 실제 점검 결과

| 항목 | 실행/근거 | 실제 결과 |
|---|---|---|
| Docker | `docker info --format '{{.ServerVersion}}'`, compose ps | 엔진 29.8.0, 기존 mysql healthy |
| DB | compose exec mysql, READ ONLY transaction에서 VERSION/information_schema/flyway 이력만 SELECT | MySQL 8.4.11, 테이블 2개, V1 success=1. 현재 V15 적용으로 간주하지 않음 |
| 보존 | 기존 song-record-dev_song_record_mysql_data 볼륨 /var/lib/mysql mount 확인 | down/reset/migrate/delete 없이 유지 |
| USB | `adb -d get-state`, OS 속성, `pm list packages --user 0` | 최초 device, Android 16, dev 앱 설치. 이후 재확인 no devices found로 현재 재연결 대기. 실기 통과를 의미하지 않음 |
| Flutter | `flutter test --no-pub test/auth_session_test.dart test/identity_link_test.dart test/identity_link_http_test.dart test/account_store_test.dart` | exit 0, 49 통과 / Windows symlink 권한으로 1 skipped |
| 서버 인증 | `gradlew.bat test --offline --no-daemon --tests '*SessionServiceTests' --tests '*OwnershipTests' --tests '*IdentityLinkTests' --tests '*AccountRegistrationTests'` | 실행 전 loopback connection 오류. 아래 재시도 포함 3회 실패, 테스트 결과 없음 |
| 자동화 | `pwsh -File tools/workflow.ps1 -Mode Quick`, PowerShell AST parse | 출처·Python 3개·PowerShell 36개·diff 검사 통과 |
| 이전 정확한 SHA CI | c5161fa: CI 36534011080 / API contract 36534011153 / Idempotency MySQL 36534011142 / Development workflow 36534011012 | 모두 성공. 이번 변경의 CI 증거를 대신하지 않음 |

서버 재시도: 기본 → `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` →
`-Dorg.gradle.jvmargs=` 및 no-daemon. 모두 `Unable to establish loopback connection`으로
테스트 시작 전 중단. 일시 환경 변수만 사용했으며 전역 설정/방화벽/권한을 변경하지 않았다.
동일 문제 3회 기준으로 추가 반복 중지. 앱의 H2 테스트는 매번 UUID 메모리 DB를 사용하므로
개발 MySQL 데이터를 읽거나 변경하지 않는다. 환경을 복구한 후 동일 명령을 재개한다.

## 속도: 설정과 관측 분리

| 실행 | 요청/설정 | 실제 관측 |
|---|---|---|
| 마스터 | 사용자 config: Astra / medium / service_tier=default, features.fast_mode 키 없음 | 현재 turn_context에 Astra/medium 있음. service_tier 필드 없음. Standard/Fast 실제 적용 **미확인** |
| 작업자 | run-agent Sensitive: Astra/high, default, fast_mode=false, ChatGPT 로그인 | CLI 헤더 Astra/high 확인, 실제 서버 tier 미노출 |
| 검수자 | 별도 run-agent Sensitive, 같은 속도 요청 | CLI 헤더 Astra/high 확인. 보완 검수는 지적에 따라 Astra/xhigh로 상향; 서버 tier 미확인 |

fast_mode 키 없음만으로 Fast 켜짐으로 단정하지 않는다. 요청 default를 실제 처리 tier로
과장하지 않는다. 내장 협업 도구가 priority만 표시하므로 해당 경로는 사용하지 않았다.
마스터 모델을 자동 변경하지 않았으며, 높은 위험의 정책 검토를 별도 Astra/high에 맡겼다.
누락/논리 오류/검수 지적은 실패 횟수와 무관하게 Finding으로 상향한다. 환경 오류만으로는
상향하지 않는다. runner는 동일 문제 3회 실패 이후 재실행을 차단한다.

## GitHub 403 원인과 영향

branches/main/protection와 rules/branches/main 모두 서버가
`Upgrade to GitHub Pro or make this repository public to enable this feature.`로 응답했다.
비공개 저장소 요금제의 기능 제한이다. ChatGPT Pro와 GitHub 요금제는 별개다.
보호 상태를 조회·증명하는 단계가 막히며 `-InspectPolicy`는 PENDING을 유지한다.
일반 Git 읽기/커밋/푸시와 Actions 조회·정확한 SHA의 자체 필수 CI 확인은 가능하다.
보호 없음으로 단정하지 않으며 공개 전환·요금제 변경·권한 확대·보호 해제는 하지 않는다.

## 컨디션과 P10 착수 판정

[D06](../decisions/D06-condition-tags.md)은 P00-06 사용자 승인에 근거하여 네 고정 코드/null,
GET 카탈로그, 쓰기 405를 명시한다. [요구사항](../requirements.md) R029/X05와도 일치한다.
P09-07b 구현의 사용자별 UUID CRUD/V15가 이 결정을 대체했다는 승인 기록은 찾지 못했다.
**기존 승인 D06 유지가 권장안이자 현재 기준**이다. 새로운 제품 선택을 요구할 필요는 없다.
사용자 정의 컨디션을 새 정책으로 원할 때만 별도 승인과 결정 변경이 필요하다.
기존 custom 데이터/스냅샷/관계를 삭제하거나 네 값으로 임의 변환해서는 안 된다.

P06-06/07/08 문서에 로그인·토큰 갱신·두 계정 녹음 격리 실기가 대기로 남아 있다.
자동 테스트가 실기 대신이 아니며 과거 다른 대화의 검증을 추정하지 않는다.
**P10-02b 실제 HTTP 송신 구현 착수 보류.** 다음은 **P09-07b-C1 (후속 보정 ID)**:
D06과 API/앱/큐 계약의 차이를 정리하고, 기존 자료를 보존하는 보정안과 테스트를 구현한다.
병행 가능한 일은 P06 실기 준비 및 DB 마이그레이션/백업 계획 검토이며,
실기용 서버 준비 전 사용자에게 로그인/녹음을 요구하지 않는다.

## 휴대폰 알림

무료 ntfy.sh와 Android ntfy 앱. 회원가입·유료 API·구독 추가 없음.
무작위 192-bit topic은 `.local/workflow/phone/config.json`에만 저장한다.
공유 서버에서 topic을 아는 사람은 구독할 수 있으므로 개인정보·로그·비밀을 넣지 않는다.
script는 작업 ID와 고정 요청 문구만 허용하고 캐시를 끈다. 오프라인이면 놓칠 수 있어
응답이 없을 때 재확인하며 서버 접수만으로 실기나 수신을 완료 처리하지 않는다.
60초 전송 간격 제한(응답 유실 UNKNOWN 시도도 포함), 자동 재시도 없음. 앱 내부 메시지는 푸시 성공 증거가 아니다.

사용자가 설치·알림 허용을 확인했다. 첫 주제 길이 오류 HTTP400은 51자로 수정 후 해결했다.
USB deep link 구독 연결 및 WORKFLOW-02 시험 알림 서버 접수 성공. 첫 수신 화면은 비어 있어 재전송했고, 사용자가 휴대폰 알림창에서 실제 받았다고 확인했다. Confirm 기록 완료. **휴대폰 알림 설정 완료**.
폰 테스트는 필요 시 ID+PhoneTest 알림을 보내고, 대화에 이유·조작·기대 결과를 남긴다.

명령: `pwsh -File tools/phone-notify.ps1 -Mode Init`, `-Mode Subscribe -Adb <adb 경로>`,
`-Mode Send -TaskId P06-08 -Kind PhoneTest`. Confirm은 실제 사용자 수신 답변 뒤에만 실행한다.

공식 근거: [ntfy Android/deep link](https://docs.ntfy.sh/subscribe/phone/),
[무료 사용/공개 topic](https://docs.ntfy.sh/faq/), [Codex 속도](https://learn.chatgpt.com/docs/agent-configuration/speed).

## 변경 파일과 학습

AGENTS.md, development-workflow/progress, 이 보고서, run-agent/workflow-common/github-check,
phone-notify 및 workflow-gates. 다음 기능 구현은 포함하지 않는다.
핵심 개념은 **접수와 완료의 분리**다. 푸시 서버 접수는 사람이 읽었다는 증거가 아니고,
CI 성공은 실제 기기의 계정 격리 증거가 아니다. DB 연결 성공도 스키마 최신성을 뜻하지 않는다.

## 검수와 최종 커밋

작업자 Astra/high는 D06 유지·P10 보류·데이터 보존 판단을 독립 검토했다.
별도 검수자 Astra/high 지적: 최종 USB 상태 누락, 불확실 전송의 간격 제한 누락, 전체 diff 증거 누락. USB 상태를 보완하고 전송 전 UNKNOWN 시도 기록을 별도로 저장해 실패도 60초 제한에 포함했다. 전체 staged diff/제외 규칙/테스트를 전달해 Astra/xhigh 재검수한다.

재검수에서 오래된 receipt 오확인과 동시 전송 경쟁을 지적하여 attempt_id 연결 및 배타적 파일 잠금을 추가했다. 실제 HTTP 없는 모의 테스트로 UNKNOWN 재전송 제한·이전 receipt 확인 거부·잠긴 송신의 HTTP 미호출을 검증했다. Quick 전체 통과(36개 판정 테스트). 사용자 수신 확인은 잠금 보완 전 실제 trial에 대한 답변이며 새 코드를 실행한 휴대폰 실기로 과장하지 않는다.

최종 Astra/xhigh 검수: 두 결함 해결, 추가 커밋 차단 결함 없음. 비차단 시험 보강(만료된 시각에서 잠금 차단, 양쪽 접수 상태에서 다른 attempt ID 거절)도 반영했다. 로컬 상태 DB 스키마에서도 service_tier/fast_mode 전용 열은 발견되지 않아 실제 속도 미확인을 유지한다.
