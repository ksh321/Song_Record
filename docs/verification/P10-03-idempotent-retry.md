# P10-03 멱등 재시도 — 구현 중

근거: 외부 원본 코드구현계획서 검색본 `docs/reference/search/plan.txt` p00581~p00583, 요구사항 R037/R050.
P10-02b 다음 단계. 아직 완료가 아니며 UI/주기 실행·큐 재시도 영속화는 연결 전이다.

## 현재 변경

- `retry_policy.dart`: 최초 송신 뒤 추가 자동 시도 3회, 실패 확인 시각부터 1/5/15분. 수동 시도로 자동 예산을 초기화하지 않는다.
- 인증·한도·파일·유효성 오류와 4xx는 자동 대상에서 제외한다. 코드 토큰을 비교하여 PROFILE을 FILE로 오인하지 않는다.
- `mutation_transport.dart`: Socket/timeout/HTTP 연결 실패만 별도 유형으로 표시한다. 인증·본문·원시 예외는 저장하지 않는다.
- `metadata_dispatcher.dart`: 네트워크 오류와 DB/프로그래밍 오류를 분리한다. DB ACK 실패는 롤백 후 SENDING 상태로 예외를 전파하며 통신 실패라고 기록하지 않는다. 401/403은 해당 회차 전송을 종료한다.

## 실제 검증

- `flutter test --no-pub test/metadata_dispatcher_test.dart test/retry_policy_test.dart --reporter expanded`: 종료 0, 24 통과.
- `flutter analyze --no-pub`: 종료 0, 문제 없음.
- 기존 ACK 롤백 테스트는 예외 전파와 SENDING 보존으로 기대를 강화했다. 테스트 삭제·CI 비활성화 없음.
- Astra/high 별도 검수의 분류 P2 두 건(유효성 우선/부분 문자열 오인)을 수정했다. Astra/xhigh 재검수 진행 중.
- 작업자 Astra/high는 계정별 횟수·일정 보존과 마이그레이션 패치를 별도 검토 중이다. default/Fast 끔 요청, 실제 처리 tier 미확인.

## 남은 구현과 재개 위치

자동 횟수 원자 차감, 저장된 동일 HTTP 요청 재사용, v1/v2→v3 보존 이관, 새 계정 세션에서 SENDING 회수,
수동 재시도 API, 시계·재시작·동시성·계정 변경 회귀 검증을 연결한다. 같은 요청의 서버 멱등 영수증/충돌 처리와 구분한다.
사용자 기존 검증 범위를 유지하며 이번 준비를 새 실기 완료로 확대하지 않는다. 아직 제품 커밋/CI 없음.

후속 xhigh 검수: 401/403 헤더 수신 후 본문 timeout 시 상태 유실을 지적했다. transport 예외에 받은 status를 보존하고 dispatcher 회차를 중단하도록 보완했다.
실제 로컬 HTTP 서버의 401 헤더/불완전 본문으로 검증했다. 관련 두 테스트 파일 재실행 종료 0, 25 통과. 이번 결과는 새 변경만의 검증이며 과거 사용자 실기를 반복하지 않았다.
DB 연결 작업자 제안은 수신 완료했고 아직 미적용이다. P10-02b 선행 SHA ae678578의 필수 CI 4개 완료를 확인했다.

## 최신 구현/검증 — core 연결

위 준비 단계 이후 `retry_controls.dart`와 v3 보조 테이블/monotonic trigger를 연결했다. v1/v2 데이터를 재생성하지 않고 증분 추가한다.
재시도 자동 예산은 claim 트랜잭션에서 차감한다. 신규 계정 open에서 SENDING을 한 번 회수하고 재오픈으로 기한을 미루지 않는다.
기존 이력이 불명확하면 예산 NULL과 수동 대기로 보존한다. 수동 한 번은 자동 예산을 재충전하지 않는다.
LocalRepository의 retryStatus/retryMutation/nextAutomaticRetryAt을 제공한다. BLOCKED 상태의 RETRY도 원인 해결 후 명시적 수동 1회만 허용한다.
검증한 frozen 재송신과 신규 변경의 기준선 검사를 구분한다. 기존 요청의 본문/op_id/base_revision을 바꾸지 않으며 같은 대상의 앞선 작업 순서는 유지한다.

- 관련 6개 테스트 파일 최초 통합: 종료 0, 77 통과·Windows symlink 권한 1 skipped. 기존 사용자 기능 검증을 되돌리지 않는다.
- v2 이관·파일 보존·예산/attempt 롤백·수동 인증 재개 추가 후 `mutation_retry_test.dart`: 종료 0, 7 통과.
- 최종 검수 지적 보완 후 `mutation_retry_test.dart metadata_dispatcher_test.dart dependency_planner_test.dart`: 종료 0, 41 통과. 401 timeout·invalid UTF8·403 oversized 본문 실제 HTTP 회귀 포함.
- `flutter analyze --no-pub`: import 순서/중괄호 info를 수정 후 종료 0, 문제 없음.
- `dart run drift_dev make-migrations --no-test`: v3 재생성 일치 종료 0. v1/v2 snapshot 보존.
- 최종 Astra/xhigh 재검수 중. 아직 제품 커밋·정확한 SHA CI는 없음.

현재 범위는 core 송신/재시도 API다. 앱의 주기 실행·로그인/lifecycle 연결·사용자 수동 화면은 후속 P10-03b로 추적하며 전체 P10-03 완료로 표시하지 않는다.
문제 P10-AUTH-BODY: timeout 보완 후 format 오류 누락을 추가 검수에서 발견해 보완했고 세 종류 회귀가 통과했다. 동일 문제 3회 실패 기준에 도달하지 않았다.

## core 최종 검수 및 로컬 통합 결과

Astra/xhigh P1(서버 기준선이 더 최신인 replay ACK 정체)을 수정했다. 검증된 같은 요청의 성공 영수증은 ACK하되 최신 metadata/local input/tombstone을 덮어쓰지 않는다.
별도 최종 검수는 기존 P1 해소·새 차단 결함 없음으로 판정했다. 비차단 권고인 동일 revision tombstone 사례도 추가 실행했다.
- 관련 6개 파일 최종 통합 `flutter test --no-pub ...`: 종료 0, 84 통과·기존 Windows symlink 권한 1 skipped.
- 추가 tombstone 독립 분기 후 `flutter test --no-pub test/mutation_retry_test.dart --reporter expanded`: 종료 0, 11 통과.
- 최신 ACK 변경 `flutter analyze --no-pub`: 종료 0, 문제 없음.
대상 제품 커밋은 이 절과 core 구현을 함께 반영한 Git history로 식별하며 푸시 후 정확한 SHA CI를 확인한다. 아직 전체 P10-03 완료가 아니다.
다음 P10-03b는 설정의 동기화 상태/수동 재시도와 foreground 실행 연결이다. 별도 Astra/high 작업자가 실제 main/LoginGate/설정/원본 HTML을 대조해 제안을 남겼다. 새 연결의 폰 조작이 필요해지면 해당 범위만 알린다.
