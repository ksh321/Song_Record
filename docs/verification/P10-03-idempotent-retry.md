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
