# P10-05k — 일관된 초기 스냅샷: 중단 재개 수신 실행기

2026-09-30. 계획서 P10-05 ‘일관된 초기 스냅샷’ p00588~589 및 D09/R040·R041의 후속 세부 실행 ID다. j의 HTTP/조건부 저장 기반과 a~i의 서버·수신·해시·원자 적용을 연결한다.

## 구현

`apps/mobile/lib/core/sync/snapshot_receiver.dart`의 step은 최대 HTTP 한 번만 수행한다. REQUESTED를 디스크에 먼저 저장하고 같은 op_id로 생성 요청을 재개한다. BUILDING 상태 조회→READY manifest 고정→19종 엔터티별 저장된 cursor/ordinal을 이어 받기→전체 검증→기준/커서 원자 적용 순서다. 메모리 타이머나 응답 대기 polling을 내부에 만들지 않았다.

동시에 들어온 같은 실행기의 호출은 진행 중 Future를 공유한다. 지연401/403이면 authenticationRequired를 유지하며 확인된 인증 재개 호출 전 자동 후속 요청을 하지 않는다. 계정 전환 응답은 저장하지 않는다. 410/INVALID_CURSOR/로컬 만료는 미완성 staging과 resume만 정리하고 새 요청을 같은 step 안에서 보내지 않는다. 실제 원본·미전송·파일 삭제 없음.

`AccountStore.hasCompleteBaseline`으로 기준 완료 표시를 읽는다. 커서 숫자 존재만으로 완료를 추정하지 않는다. 이미 기준이 완료되고 resume이 없으면 새 사본을 중복 생성하지 않는다.

## 검증·현재 모델 검토

```text
flutter test --no-pub test/snapshot_receiver_test.dart --reporter expanded
flutter test --no-pub test/snapshot_receiver_test.dart test/snapshot_transport_test.dart test/snapshot_download_store_test.dart test/account_store_test.dart --reporter expanded
flutter analyze --no-pub lib/core/database/account_store.dart lib/core/sync/snapshot_receiver.dart test/snapshot_receiver_test.dart
```

첫 수신5 통과 후 INVALID_CURSOR와 로그아웃 경합을 추가했다. 최종 통합 **50 통과/기존 Windows 링크 권한1 skip**, 분석 No issues found. 실제 임시 SQLite 파일과 합성 transport를 사용했다. 신규 수신7개: 요청 유실 후 재열기·같은 op_id, 지연401 및403 각각 중복 호출시 전송1회와 인증 재개 후만 재전송,19종 중간 재시작·커서7 원자 적용·중복생성없음,410정리,잘못된 페이지cursor 정리,로그아웃 후 지연응답 저장 차단.

현재 모델 별도 검토에서 서버의 실제 receipt/status/error envelope, D09 TTL/재시도, 저장 SQL·기존 trigger, 인증 차단 결과 전달을 대조했다. cursor 존재와 baseline 완료를 혼동하는 조건을 보완했다. 분석의 중괄호 권고를 수정했다. 독립 에이전트 검수/폰 실기 아님. 로그 .local/workflow/p10-05-receiver-test.log, p10-05-receiver-integration.log.

## 남은 범위

새 실행기는 아직 앱 화면/스케줄러와 연결하지 않았다. 호출자는 계정별 단일 실행기를 유지하고 인증 재개를 검증한 뒤 호출해야 한다. 무조건 즉시 반복 호출하는 루프로 사용하지 않는다. 기존 metadata 조회에 기준 사본을 반영하는 투영, 실제 앱 동작 연결 및 그 영향 검증이 남았다. 전체 P10-05 미완료. 커밋/정확 SHA 필수 CI 후속 확인. 사용자 확인 대기0건.

추가 검토 근거: flutter test --no-pub test/account_store_test.dart --plain-name 'cursor alone does not mark the snapshot baseline complete' --reporter expanded 1 통과. 실제 저장된 cursor0/baseline_complete0을 완료로 오판하지 않음을 확인했다.
