# P10-05d — 지속 작업 권한·원자 접수·생성 실행

2026-09-30. P10-05/D09, S03~S05/S10/S11/S14. 새 Codex 세션 없이 현재 모델 직접 구현·검토.

## 구현과 근거

- SnapshotAuthority는 sync 패키지 내부의 서버 권한이다. 요청은 기존 AccountAccess, 작업 실행은 실제 DB의 SNAPSHOT_BUILD/RUNNING/lease_token/미만료 lease/계정 ACTIVE/같은 소유 사본을 대조한다. 사용자 로그인 토큰을 job payload나 snapshot에 저장하지 않는다.
- 작업은 자기 사본만 수정할 수 있다. 최종 쓰기 트랜잭션의 job row 잠금/lease 재확인이 실패하면 capture/행/예약/READY 게시가 함께 rollback된다. SnapshotBuildStore 쓰기 트랜잭션은 READ COMMITTED로 최신 권한을 재확인하고, 원본 읽기뷰는 별도 REPEATABLE READ 연결로 유지한다.
- SnapshotRequests는 기존 IdempotentMutations 트랜잭션 안에서 beginJoined와 JobQueue.enqueue를 실행한다. receipt/header/job이 함께 commit되며 enqueue 실패 시 모두 rollback. 요청 재전송은 기존202 응답/동일 작업·사본을 반환한다. 엄격한 schema_version=1 검사와 overflow 값 거절. 저장 job payload는 `{}`뿐이다.
- SnapshotWorker는 한 번의 durable tick에서 실제 job lease로 읽기뷰→원본 batch→게시를 실행한다. READY를 이미 만든 뒤 완료 응답을 잃었으면 재생성/TTL 연장 없이 job만 완료한다. 새 유효 job lease가 부분 생성 시도를 다시 맡으면 전체 파생 행을 버리고 새 attempt/읽기뷰로 시작한다. 오래된 job의 쓰기는 최종 fence에서 거절된다.
- 요청 사용자의 restartExpired는 기존처럼 lease 만료 후만 가능하다. 만료 전 부분 시도 재시작은 패키지 내부의 검증된 job 권한에만 허용했다. begin의 동일 attempt 반환 자체가 새 실행 권한이 되지 않도록 분리했다.

## 실제 검증

권한 연결 후 관련 snapshot34 통과. 원자 접수 추가 후 source7 통과. 실행 작업 연결 뒤 아래 실제 명령은 **69 통과**(source9 + Job14 + Idempotency16 + 실제 MySQL Idempotency30), 실패/오류/skip0:

```text
gradlew.bat test --tests '*MySqlSnapshotSourceRowsTests' --tests '*JobTests' --tests '*IdempotencyTests' --offline --no-daemon
```

MySqlIdempotencyTests도 wildcard에 포함돼 기존3306의 해당 테스트가 만든 p07_test_<UUID> DB만 사용/정리했다. Snapshot tests는3307의 p10_source_test_<UUID> DB만 사용/정리했다. 기존 앱 DB/볼륨은 보존했다. 실행1분56초로 완료됐으며 실패나 중단으로 판정하지 않았다. 완료 전 JVM 진단에서 선택한2736은 테스트 JVM이 아니었으므로 해당 로그를 테스트 교착 근거로 사용하지 않는다. 실행 중 테스트/개발 API 프로세스를 중지하지 않았다.

실제 검증: 위조/만료 lease, 다른 사본 접근, DELETING 계정 거절, job fence가 commit까지 다른 연결의 SKIP LOCKED 접근 차단, 최종 fence 실패 시 row/byte rollback, 원자 접수 재전송, enqueue 실패 rollback, 실제 durable worker READY 완성/재처리 TTL 불변, 부분 시도 폐기 후 실제 원본 재생성. fixture job은 각 테스트 전에 해당 일회용 DB 안에서만 격리해 전역 claim의 테스트 순서 의존을 막았다.

최종 관련 snapshot38 통합 결과는 아래 후속 기록. 로그 .local/workflow/p10-05-authority-test.log, p10-05-requests-test.log, p10-05-worker-test.log, p10-05-worker-integration.log. 초기 편집 도구의 cp949 읽기 오류는 UTF-8 명시로 보완했으며 제품 실패로 계산하지 않는다.

현재 모델 검토: D09 및 기존 JobQueue/IdempotentMutations 실제 트랜잭션 경계와 대조. REQUIRES_NEW로 header만 먼저 commit되는 오류를 피하려 명시적 joined 진입점을 추가했고 자격 증명 저장 없이 job 권한을 검증했다. 구현 검토를 독립 에이전트 검수라고 표현하지 않는다. 모델 자동 변경/실제 tier 미확인 유지.

## 남은 연결

HTTP/Bean/scheduler는 아직 노출하지 않았다. 실제 설정에서는 스냅샷 전용 JobQueue의 lease를 생성 최대10분에 맞춰야 한다(기존 일반 job2분을 그대로 쓰지 않음). 실패/만료 정리, 청소 후 멱등 재요청/만료 응답, 상태 조회/OpenAPI 및 모바일 staging이 남았다. 실행 중지/재시작을 외부 상시 서비스로 보장하지 않는다. 전체 P10-05 완료 또는 실기 통과로 확대하지 않는다. 사용자 확인 대기0건.

최종 관련 snapshot38 테스트 통과(실제 MySQL24 + H2/커서14), 실패0/오류0/skip0. 명령은 앞선 snapshot 통합 목록에 MySqlSnapshotSourceRowsTests를 포함한 동일 선택.

커밋 fd5955117e27d4b5f175b727bfdfa9cd5ca50749 일반 push 완료. 정확 HEAD 필수 CI4 PASS: CI36672504894, API contract36672505005, Idempotency MySQL36672504953, Development workflow36672504944. 위 남은 연결은 당시 상태이며 HTTP/정리 후속은 P10-05e-snapshot-http.md에서 진행한다.
