# P10-04b-GATE — 매핑 후 전송 자격과 논리 순서

계획 P10-04 p00584~586 / 설계 p00293. 원자 매핑의 후속 보류 근거를 실제 claim·수동 재시도·예약 계산에 적용하는 기반이다. dispatcher 매핑 연결이나 전체 P10-04 완료가 아니다.

- `mapping_eligibility.dart`: 계정 DB의 alias/hold/supersession을 읽어 전송 자격과 논리 순서를 계산한다. 원본 queue/wire/attempt/예산/스키마를 수정하지 않는다.
- `local_models.dart`, `dependency_planner.dart`: 보류 요청도 그룹 선두 자리를 유지한다. 같은 canonical으로 모이는 source들의 순서를 합치며, 보류된 요청을 목록에서 지워 후속 요청이 추월하는 일을 막는다.
- `retry_controls.dart`, `account_store.dart`: frozen 재시도 예외보다 매핑 보류를 먼저 검사한다. 수동 승인과 실제 claim을 함께 막고 다음 예약도 같은 projection을 사용한다.
- 단일 미전송 PENDING PATCH 대체만 논리 순서를 상속한다. 지원하지 않는 chain, 이미 시도한 original, 다른 대상 대체는 영향 그룹만 보류한다. 무관한 tag는 전송 가능하다. REPLAY_ORIGINAL의 검증된 재전송 예외·lateACK·새 편집 처리·대체 생성은 후속 계약이다.

## 실제 검증

`flutter test --no-pub test/canonical_song_store_test.dart test/mutation_retry_test.dart test/dependency_planner_test.dart test/metadata_dispatcher_test.dart`: **86 통과**. `flutter analyze --no-pub`: **No issues found**. 처음 실행에서는 테스트 통과 후 import 정렬 경고가 있어 정렬한 최종 코드로 재검증했다. 추가 테스트 적용용 임시 Python 스크립트는 따옴표 SyntaxError 1회 후 수정했으며 제품 코드 실패로 기록하지 않는다.

실제 SQLite: BLOCK/REPLAY_ORIGINAL 보류, frozen wire/예산 유지, 수동 승인·기한 차단, alias 선두 순서, 단일 대체 논리 순서, hold 우회 차단, chain 격리, 전송 이력 original 거절, 다른 대상 대체 격리, fan-in과 독립 tag 진행. 기존 atomic rollback/소유권/반복 receipt 테스트 유지.

작업자 Astra/high(동기화·DB), 별도 검수자 Astra/high 진행 중. default/Standard·Fast 끔 요청, 실제 CLI 모델/추론은 실행 기록으로 구분하며 서버 tier 미확인. 현재 미커밋·CI 전으로 완료 판정하지 않는다. 상세 로그는 `.local/workflow/p10-04b-gate-final-test.log`, `p10-04b-gate-final-analyze.log`.
별도 Astra/high 검수 1회 수정 필요: SENDING 녹음 PATCH 뒤 매핑된 local song_id가 늦은 ACK source snapshot으로 되돌아갈 수 있음. Gate1 문제로 기록하고 P1이므로 3회를 기다리지 않고 Astra/xhigh 작업자로 상향했다. 현재 미커밋 보완 중. 86 통과는 이 경합까지 완료했다는 뜻이 아니다.

Astra/xhigh 작업자 보완 적용: 실제 SENDING request의 ACK는 수용하되 active hold가 있으면 local_payload를 유지한다. 서버 더 높은 revision/tombstone 보호 및 hold/wire/예산은 보존. ACK 이전 같은 대상 후속 mutation이 없는 진짜 경합, 더 높은 서버 rev, tombstone, no-hold 정상 ACK 4사례 추가 후 관련 4파일 90 통과·분석 No issues found. noalias/nohold/nosupersession이면 과거 payload 전체 스캔을 건너뛰는 빠른 경로도 적용했다. 현재 별도 Astra/xhigh 재검수 진행 중. 코드/테스트는 미커밋.

최종 별도 Astra/xhigh 검수: 실제 diff·소스·90 통과/분석 로그 대조 후 추가 차단 결함 없음. 기존 P1 보정, noalias 기존 판단·예산 보존 및 ACKED hold 격리 확인. 검수자는 직접 테스트 실행/커밋 CI를 판정하지 않았으며 master가 실행 로그와 추후 정확한 SHA CI로 보완한다. 현재 누적 검수 실패 1회/최대 추론 실패 0회, 보완 후 검수 통과.
