# P10-04b-ATOMIC — 원자 매핑 저장소 기반

계획 P10-04(p00584~p00586), 설계 p00293의 동일 TJ canonical 매핑을 위한 저장소 API다. **자동 송신에 연결하지 않은 기반 코드**이며 전체 P10-04 완료가 아니다.

- `account_store.dart`: `applyCanonicalSongReceipt`가 계정 lease·실제 frozen request·attempt 소유권을 검사하고 canonical server copy, alias, 편집 근거, 관련 mutation 보류 근거, 로컬 참조, 원본 CREATE ACK와 재시도 종료를 단일 트랜잭션에 반영한다.
- 기존 source UUID·개인 draft·파일·journal·다른 op의 payload/wire/예산을 보존한다. 높은/equal revision, tombstone, SQL NULL draft는 덮어쓰지 않는다. 참조에서 명시적 null/다른 곡 선택은 유지하며 canonical만 참조하던 독립 항목은 보류하지 않는다.
- 이미 ACK된 receipt 반복, 다른 attempt/계정, alias chain은 쓰기 없이 거절한다. 현재 direct alias만 지원한다. chain, 늦은 ACK, saveEdit, 전송 보류 gate와 실제 dispatcher 연결은 후속 구현이다.

## 실제 검증

`flutter test test/canonical_song_store_test.dart test/canonical_schema_test.dart test/metadata_dispatcher_test.dart test/mutation_retry_test.dart`: **70 통과**. `flutter analyze`: **No issues found**. `dart format` 적용, `git diff --check` 통과.

실제 SQLite의 일곱 단계 실패 주입으로 모든 테이블 rollback을 비교하고 반복 receipt, 변경된 wire/attempt, 계정 무효화, 기존 draft/파일/독립 canonical 참조 보존을 확인했다. 처음에는 isolate의 DriftRemoteException과 테스트 예상 타입이 달라 7개가 실패했다. 예외의 SQL code 1811과 injected 메시지 및 전체 DB 비교를 유지해 수정했다. experimental import 경고는 안정적인 Exception 인터페이스 사용으로 해소했다. 위 70 통과는 보완 후 실제 결과다. 환경/테스트 호환 문제를 기존 P10-03b 실패 횟수에 합치지 않는다.

작업자 Astra/high, 별도 검수자 Astra/high(계정·DB 원자성 위험). 요청 default/Standard·Fast 끔, CLI model/high 확인, 실제 서버 tier 미확인. 1차 정적 검수에서 범위 내 차단 없음. 실제 schema/retry 구현을 추가 제공한 교차 검수에서도 차단 없음. 외래 키·불변 트리거·finish의 동일 트랜잭션 참여를 확인해 근거 공백을 해소했다. 상세 실행 로그는 `.local/workflow/p10-04b-atomic-final-test.log`, 분석 로그는 같은 prefix의 `final-analyze.log`다.

커밋·해당 SHA CI는 아직 대기다. 실제 앱 경로에 연결하지 않았으므로 새 폰 실기는 요청하지 않는다. USER-001 설정 확인 및 P10-03b 새 UI 실기는 별도 유지한다. 기존 사용자 검증 범위를 되돌리지 않는다.