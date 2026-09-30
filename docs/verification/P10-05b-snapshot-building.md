# P10-05b — BUILDING 예약·분할 저장·READY 게시 기반

2026-09-30. 요구사항 P10-05, D09, 공통 수용 사례 S03/S10/S12/S13/S14. 기존 V7 snapshot_header/entry/capacity 및 8개 trigger를 변경하지 않고 사용했다. 새 세션 위임 없이 현재 모델 직접 구현·검토.

## 구현

SnapshotBuildStore는 서버 내부 서비스이며 아직 HTTP API/Bean에 노출하지 않았다.

- begin: 인증 계정의 동일 op_id는 같은 사본/attempt를 반환. 계정별 활성 슬롯2개를 초과하면 429, 기존 사본을 교체하지 않는다. 새로운 사본의 초기 예약은0.
- capture: 동일 읽기뷰 기준 cursor/captured_at을 한 번 고정. 기존 기준을 다시 쓰거나 다른 attempt로 저장할 수 없다.
- append: 1~100행씩 MySQL이 실제 저장할 UTF-8 JSON 크기를 계산하고 용량을 먼저 예약한다. 사본100MiB/전역1GiB를 초과하면 rollback. 전역 capacity→개별 header 순서로 잠그고 기존 trigger가 행/바이트 수를 관리한다.
- publish: 모든 엔터티의 예상 개수와 실제 행/연속 ordinal을 대조하고 정규 JSON의 manifest hash를 계산한다. 검증·인증·attempt/lease 재확인 후 READY/ready_at/30분 expires_at을 한 트랜잭션으로 게시한다. 이후 행 추가를 거절한다.
- manifest hash 내부 계약 v1: ASCII domain `SongRecord:snapshot-manifest:1`, 8바이트 big-endian baseline cursor 뒤 DB entity/ordinal 순으로 4바이트 길이+ASCII entity, 8바이트 ordinal, UUID16바이트, 4바이트 길이+canonical UTF-8 payload를 SHA-256. 실제 키·개인 데이터 없음. HTTP manifest 전체 형식/클라이언트 검증은 후속 계약이다.

## 실제 검증과 검토

`services/api`에서 기존 로컬 설정을 메모리로만 읽어 P07_MYSQL_CI=true/P10_MYSQL_PORT=3307로 실행했다. 테스트마다 새 p10_build_test_<UUID> DB를 만들고 해당 DB만 정리했다. 개발 DB·볼륨은 보존했다.

```text
gradlew.bat test --tests '*MySqlSnapshotBuildStoreTests' --offline --no-daemon
gradlew.bat test --tests '*SnapshotPageCursorTests' --tests '*SnapshotPagesTests' --tests '*SnapshotReadViewTests' --tests '*MySqlSnapshotBuildStoreTests' --offline --no-daemon
```

첫 단계4, 게시 추가7, 동시 요청/인증 취소 보완 후 **MySQL9 통과**. 최종 연관 통합 **28 테스트 통과**, 실패/오류/skip0. 원본 V7 DDL/8trigger를 실제 MySQL8.4에 설치해 검증했다. 로그 .local/workflow/p10-05-build-store-test.log, p10-05-build-integration.log; 핵심 결과는 이 문서에 보존한다.

검사: 동일 op 경쟁 시 attempt1개, 슬롯2개 제한, exact MySQL JSON byte 예약, 미완성 batch 원자 rollback, 다른 계정/attempt/만료 lease 거절, capture 재설정 거절, ordinal gap/개수 불일치 게시 거절, READY 페이지 연계/TTL 보존, 게시 직전 인증 취소. 사본 상한/전역 상한은 각각 별도로 도달하게 하여 다른 검사에 가려진 거짓 통과를 막았다.

현재 모델 코드 검토는 D09와 V7 trigger/실제 diff/테스트 결과를 대조했다. 용량 예약/행 삽입/상태 게시 트랜잭션과 잠금 순서, 같은 op 재전송 시 TTL 불변, 공개 자료의 로그 redaction 확인. 기존 CI/테스트는 유지하고 MySQL CI에 새 테스트를 추가했다. 난이도 목표는 인증/DB high 이상이며 실제 현재 모델 변경·Standard tier는 미확인, 새 Worker/Reviewer 없음.

## 남은 연결

전체 업무 엔터티 추출, 생성 실행 조율, 실패/재시작 attempt 전체 폐기·재생성, 5분 정리, durable idempotency와 cleanup 뒤 같은 op 재요청 처리, HTTP/OpenAPI/계정 삭제 연계, 모바일 staging은 아직 미구현이다. READY 게시 내부 검증은 추출기가 모든 엔터티 완료 후 만든 개수표를 받는 계약이며 외부 요청이 이 표를 직접 제공하도록 노출하지 않는다. 전체 P10-05 완료나 실기 통과로 기록하지 않는다. 사용자 확인 대기0건.

커밋/정확 SHA 필수 CI는 후속 기록. 다음은 기존 데이터를 포함한 명시적 엔터티 추출과 실패 복구를 연결한다.

최종: d06c1397c8afdb861e1d96145539707de22dd2b0 커밋/push 및 필수 CI4 PASS. CI36670115445/API contract36670115390/Idempotency MySQL36670115332/Development workflow36670115353. b 기반 범위만 완료, 전체 P10-05는 진행 중.
