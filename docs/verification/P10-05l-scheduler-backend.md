# P10-05l — 일관된 초기 스냅샷: 전경 스케줄러 연결 계층

2026-10-01. 원본 P10-05(계획서 p00588~589), D09의 초기 수신을 기존 SyncController에 합성하는 세부 작업이다. l은 재시도 횟수가 아닌 세부 식별자다.

- SnapshotStepper 경계를 도입하고 SnapshotSyncBackend를 추가했다. 초기 기준선 완료 전 송신을 보류하고 기존 단일 전경 스케줄러만 사용한다. 진행은 1초, BUILDING 조회는 5초 이후로 제한한다.
- 401/403은 세션 조회 단계와 수신 결과 모두 자동 후속 실행을 막는다. 검증된 재인증 뒤 새 계정별 backend를 만들어야 한다. 일시 오류는 기존 컨트롤러의 제한된 오류 복구로 전달한다.
- 아직 main/UI에는 연결하지 않았다. 19종 기준선의 조회 투영과 기존 로컬 변경 보존을 먼저 연결해야 한다. 전체 P10-05 및 폰 실기 완료가 아니다.

실제 검증:
```text
flutter test --no-pub test/snapshot_sync_backend_test.dart test/snapshot_receiver_test.dart test/sync_controller_test.dart --reporter expanded
flutter analyze --no-pub lib/core/sync/snapshot_receiver.dart lib/features/sync/snapshot_sync_backend.dart test/snapshot_sync_backend_test.dart
```
42개 통과, No issues found. 지연 인증 실패+이탈/복귀, 세션401/403, BUILDING 기한 우회 방지, 일시 오류 뒤 정상 복구를 확인했다. 최초 로그 출력 경로 오류는 실행 전 환경 오류로 수정했고 제품 수정 실패 횟수에 포함하지 않았다. 합성 입력만 사용했다.

현재 모델 별도 검토: D09 수신 완료 조건, 기존 SyncController의 단일 timer/후속 실행 차단, 계정별 인스턴스 수명을 diff/검증과 대조했다. 외부 작업자 위임 없음. 인증·동기화 위험 때문에 높은 추론이 적합하나 실제 모델/속도 변경을 확인했다고 주장하지 않는다.

변경: snapshot_receiver.dart, snapshot_sync_backend.dart, snapshot_sync_backend_test.dart. 로그 .local/workflow/p10-05l-backend-test.log. 대상 SHA는 이 제목의 Git 커밋으로 식별하며 통합 CI는 push 후 기록한다.
