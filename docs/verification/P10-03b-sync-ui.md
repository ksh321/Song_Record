# P10-03b — 동기화 실행 연결과 수동 화면 (진행 중)

2026-09-30 최신 실기 준비: 고정 2e6bd88 dev 1.0.0+1 설치 완료, Google/Kakao 로그인 모두 사용자 성공 확인. 아래 빌드 설정 미확보·로그인 준비 대기는 과거 이력이다. USER-018 새 화면 표시/Android 홈 이탈·복귀만 요청했다. 빈 큐 결과를 실제 송신/수동 접수 검증으로 확대하지 않는다. 자동 시간 동기화는 별도 환경 미해결.

최신 운영 판정: **사용자 수동 보완 후 별도 Astra/ultra 검수에서 기존 P2 해소·추가 차단 결함 없음**. 과거 누적 실패 6회·최대 수준 실패 3회는 보존한다. 사용자 직접 수정 후 명시적인 별도 검수 요청으로 재개한 것이며 자동 추가 Worker 시도가 아니다. 요청 Standard/default·Fast 끔과 실제 runtime tier 미확인을 구분한다. 코드 커밋/필수 CI와 새 폰 실기는 별도 판정한다.

사용자 실행 근거: 사용자가 Patch applied / +73 All tests passed / No issues found / Validation passed를 보고했고 master가 저장된 두 로그와 실제 코드를 대조했다. 지연된 401/403 × foreground/enabled 이탈·복귀 4개 회귀가 전송 1회·항목별 attempt `[1,0]`·예약 0회를 확인한다. RepositorySyncBackend의 automaticFollowupAllowed가 controller finally까지 전달돼 해당 회차의 queued wake를 억제한다. 명시적 수동 권한/DB 예산은 유지한다. 사용자 직접 실행은 PC 자동 테스트이며 폰 실기 완료가 아니다.

환경 이력: 사용자 터미널에서 pwsh 명령을 찾지 못해 최초 스크립트가 시작되지 않았다. Windows PowerShell 5.1.26100.9444와 기존 Codex 번들 PowerShell 7.6.5를 확인했다. 5.1 진입 후 번들 실행 파일을 지정하도록 스크립트를 보완하고 문법만 검사했으며, master가 대신 실행하거나 제품 3파일을 수정하지 않았다. 이후 사용자가 직접 성공 실행했다. 이 PATH 환경 오류는 코드 실패 횟수에 포함하지 않는다.

아래 중단/요청 기록은 사용자 수동 보완 이전의 이력이며 최신 대기 판정이 아니다.

최종 남은 P2: 첫 요청 전송 중 foreground 이탈→복귀로 `_wakeRequested`가 설정되고 첫 응답이 401/403이면 backend는 타이머만 차단한다. controller finally의 자동 followup은 이 결과를 몰라 두 번째 요청을 보낸다. 재개 제안은 인증 차단 결과를 controller에 전달하여 해당 회차에 이미 접수된 자동 followup까지 억제하고, 실제 DB 두 INITIAL 항목·지연 인증 응답·이탈/복귀에서 전송 1회와 attempt `[1,0]`을 확인하는 것이다. 명시적 사용자 재시도/DB 예산은 유지한다.

ntfy P10-03b Escalation 전송에 Astra high/xhigh → Astra ultra, 인증 차단 뒤 자동 후속 전송 문제, 실패 기록·재개 방안 판단 요청을 넣었다. 서버 접수 확인, 실제 휴대폰 수신은 미확인이다. 사용자에게 위 좁은 범위 추가 보완 허용 또는 중단 유지를 요청했다. 제품 변경은 미커밋이며 기존 main의 검증 완료 기능을 되돌리지 않는다.

| 최대 수준 시도 | 원인·보완 | 실제 결과와 판정 |
|---|---|---|
| 1 — Astra/ultra 작업자·별도 검수 | 복구 시각 별도 보존, lifecycle의 실패 초기화 제거 | controller 23/영향 44 통과. 검수에서 정지 안내 소실·검증 공백 P2 → 최대 실패 1 |
| 2 — Astra/ultra 검수 제안 적용·별도 검수 | 정지 안내 분리, 재개/종료/실제 DB 예산 검증 | 관련 42 통과·분석 통과. 50건 이후 잔여 INITIAL 예약 누락 P2 → 최대 실패 2 |
| 3 — Astra/ultra 검수 제안 적용·별도 검수 | 즉시 송신 가능 잔여 요청 예약, 인증 응답 후 타이머 차단 | DB/HTTP/controller 3파일 69 통과·최신 분석 통과. queued wake의 인증 차단 우회 P2 → 최대 실패 3·중단 |

재개 파일: `lib/features/sync/sync_controller.dart`의 `_run` finally와 `RepositorySyncBackend`의 인증 차단 전달, `test/mutation_retry_test.dart`의 실제 DB 인증 경합 회귀. 현재 작업자·검수자 프로세스는 모두 결과 수신 후 종료 0이다. 실행 성공이 검수 통과를 뜻하지 않는다. 필수 앱 커밋/CI·새 폰 실기는 남아 있다.

추가 시도 1: 복구 시각을 타이머와 분리하고 생명주기 wake에서 실패 초기화를 제거했다. busy 잠금 안의 deadline 조회 결과는 보존하고 실제 예약만 foreground/enabled로 제한한다. 명시적 “전송 다시 시도”만 내부 오류 정지를 해제하며 mutation별 예산은 바꾸지 않는다. 작업자 CLI 헤더 Astra/ultra 확인. `flutter test --no-pub test/sync_controller_test.dart --reporter expanded` 23 통과, 이어 login_gate/auth_session/app_shell/tab_navigation 포함 5파일 44 통과. `flutter analyze --no-pub` 종료 0, 문제 없음. 별도 Astra/ultra 검수 중이며 최대 수준 실패로 아직 가산하지 않았다.
위 마지막 문장은 시도 1 검수 전의 과거 기록이다. 현재 상태는 첫 문단을 따른다.

추가 시도 2: Astra/ultra 검수 제안대로 정지 안내를 조회 message와 분리하고 AUTO 항목의 정지 상태를 표시했다. 재개 버튼 화면 진입/조회/비활성/탭, 정상 1초 하한, 자동 복구 성공 후 내부 실패 초기화, 전송·수동 승인 중 종료 후 늦은 성공/예외를 검증했다. 실제 RepositorySyncBackend/SQLite에서 3회 자동 예산 소진 후 controller.resume 반복이 예산을 늘리지 않고 개별 수동 승인만 1회 허용함을 확인했다.
- `flutter test --no-pub test/sync_controller_test.dart test/mutation_retry_test.dart --reporter expanded`: 종료 0, 42 통과.
- 새 테스트의 중괄호 스타일 지적 1건을 보완한 뒤 `flutter analyze --no-pub`: 종료 0, 문제 없음. 제품 논리 실패로 합산하지 않았다.
- 독립 Astra/ultra 시도 2 검수에 실제 저장소·전송·예산 코드와 로그를 추가 제공했다. 결과 대기.

근거: 구현계획 p00582~p00583의 수동 재시도, 설계 4.2/5.3, UI_REFERENCE 공통 규칙.
원본 HTML settings에는 동기화 충돌 진입만 있고 별도 재시도 화면은 없다. 수동 재시도 요구를 수행하기 위해 기존 메뉴를 유지하며 설정에 보조 상태 진입을 추가했다. 기존 메뉴 누락/placeholder는 이번 변경으로 삭제한 것이 아니다.

## 구현

- 계정 lease마다 SyncController/LocalRepository 생성. 로그인 준비·로그아웃 busy 상태와 앱 lifecycle로 신규 전송·예약을 제어한다.
- main의 세션 콜백은 전송 허용을 인증 조회 전후 확인한다. 이미 진행 중인 네트워크 취소나 OS 백그라운드 실행을 보장하지 않는다.
- 상태 화면은 대기 정보·안전한 고정 이유·재시도를 표시한다. 원본 본문·오류·계정/기기 ID는 표시하지 않는다.
- 수동 접수는 완료가 아니다. core CAS가 허용한 요청을 포함하여 전송 가능한 대기 큐를 처리하며 이 동작을 화면에 설명한다.
- 자동/수동 작업 종료와 예약 교체를 한 경로에서 수행한다. 앱 복귀 경합은 세대 검사로 막는다.
- 내부 전송/예약 조회 오류는 30초 지연·연속 3회 제한으로 복구한다. 실제 mutation의 1/5/15분·최대 3회 예산은 core DB에서 별도로 유지한다.

## 실제 검증과 검수

- 최초 controller/화면 7 테스트 통과. 로그인·auth·탐색 포함 영향 5파일 28 통과.
- Astra/high 검수 3 P2(수동 중 복귀 누락/예약 경쟁/오류 후 예약 끊김) 보완 후 controller 11 통과, 영향 5파일 32 통과.
- Astra/xhigh 추가 P2(queued wake 오류 지연 우회/deadline null 복구 누락) 보완 후 controller 13 통과.
- 최신 flutter analyze --no-pub 종료 0, 문제 없음.
- 과거 규칙 적용 당시 P10-03b-SCHEDULER: **검수 실패 누적 3회로 사용자에게 알림**. 당시 Astra/xhigh 검수는 실패 후 deadline 조회 중 앱 이탈→복귀 시 generation이 바뀌어 타이머 설치가 취소되고, 오류 상태의 queued wake도 생략되어 복구가 멈추는 P2를 발견했다. 현재 대기 상태를 뜻하지 않으며 위 최신 판정을 따른다.
- 1차 예약 경쟁/오류 후 예약 끊김, 2차 queued wake의 지연 우회/null deadline 복구 누락을 보완했으나 3차에서 두 경로가 겹치는 경우가 남았다. 권장 보완은 실패 횟수와 최소 30초 지연을 유지하며 전경 복귀 후 예약만 다시 확보하는 것이다. 첫/두 번째 실패 중 조회 대기→이탈→복귀 회귀 테스트와 별도 검수를 재개 조건으로 제안했다. 승인 전 추가 수정·커밋하지 않는다.
- 세 번째 실패 개입 알림의 ntfy 서버 접수 확인. 실제 수신 확인은 없고, 사용자에게 보완·검수 재개 여부를 요청했다. 실패 횟수는 모델/세션 변경이나 재개로 초기화하지 않는다.
- 검수 입력에 실제 소스/결과를 제공했다. 모델·추론은 CLI 헤더, default/Fast 끔은 요청값, 실제 서버 tier 미확인.

## 실기 준비 대기

최초 USB 점검에서는 기기가 없었으나, 사용자 재연결 응답 후 `adb -d get-state` 결과 device를 확인했다. 이는 연결 준비이며 실기 통과가 아니다.
이 PC 저장소와 현재 환경에서 Google/Kakao Flutter 로그인 빌드 설정을 찾지 못해 기존 설정 파일의 경로만 요청했다. 값이나 키를 대화에 보내도록 요청하지 않았다.
기존 로컬 app-dev-debug.apk는 2026-09-22 빌드라 이번 변경 검증에 사용하지 않는다. Windows Gradle 3회 실패는 별도 환경 이슈로 유지하고 같은 시도를 반복하지 않았다.
ntfy P10-03b Intervention 서버 접수 확인. 실제 알림 수신·실기 통과는 미확인이다. 현재는 연결/설정 준비 요청이며 사용자에게 새 동작 테스트를 통과했다고 묻지 않았다.

기존 P05-08/P06 사용자 검증은 유지한다. 새 화면 표시·수동 접수·foreground 복귀·계정 전환 영향만 새 실기 대상으로 삼는다. 폰 결과 없이는 전체 P10-03 완료 금지.
P10-04 core 보존 설계는 이 대기와 독립적으로 진행한다. 파일·DB·계정 자료를 초기화하지 않는다.

## 사용자 보완 후 커밋과 후속 상태

대상 커밋 a5d0e4423e84e804d9b2552d0bea4f9ad7556381 일반 push 완료. 별도 Astra/ultra 검수는 지연 401/403 × foreground/enabled 전환의 4회귀에서 전송 1회·attempt [1,0]·예약 0을 확인하고 추가 차단 없음으로 판정했다. 저장된 사용자 실행 로그는 73 통과·분석 문제 없음이며 폰 실기로 확대하지 않는다. 해당 SHA 필수 CI 4개 모두 success: [CI 36568514644](https://github.com/ksh321/Song_Record/actions/runs/36568514644), API 36568514544, Idempotency MySQL 36568514568, Development workflow 36568514512. 각 필수 job도 모두 success.

실기 준비 요청 ntfy 서버 접수 확인. 이후 사용자는 USB 연결만 답했고 실제 device를 확인했다. 기존 로그인 설정 경로는 미확인이다. 새 빌드 없이 오래된 설치 앱을 이번 변경 실기 근거로 쓰지 않는다.


USER-018 결과: “대기 중인 정보가 없어요 뜨고 다 정상 작동”. 현재 설치 2e6bd88 dev의 빈 큐 화면·상태 확인·Android 홈 이탈/복귀 정상 사용자 확인. 비어 있지 않은 큐 송신·수동 접수·계정 격리 실기로 확대하지 않는다. 해당 새 변경 영향의 남은 fixture 준비/검증은 workflow-state의 P10-03b-FIXTURE/P10-03b-PHONE-QUEUE에서 추적하며 사용자 할 일에는 준비 후 실제 필요한 조작만 올린다.
