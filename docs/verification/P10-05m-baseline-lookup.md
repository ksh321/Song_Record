# P10-05m — 일관된 초기 스냅샷: 기준선 단건 조회

2026-10-01. P10-05(계획서 p00587~589) 및 D09의 기준 사본과 미전송 변경 분리를 위한 조회 기반 세부 작업이다. m은 실행 횟수가 아니다.

SnapshotDownloadStore.baselineRecord와 AccountStore.snapshotBaselineRecord를 추가한다. 하나의 트랜잭션에서 APPLIED 포인터와 행을 읽고 token/cursor를 함께 반환한다. 적용된 기준선 없음(null)과 해당 기준선에 행 없음(entry null)을 구별한다. 저장소 직렬화와 최종 계정 fence를 유지한다. 이미 적용한 자료는 다운로드 TTL 이후에도 읽을 수 있다.

현재 모델 별도 검토에서 SnapshotSourceRows의 resource_id가 RECORDING_TAG 등에서 반복되는 것을 확인했다. 단건 조회를 SONG/RECORDING/PLAYLIST/TAG/RECORDING_CONDITION의 고유 UUID 범위로 제한했다. 관계·로그는 기존 ordinal 페이지 조회를 유지하며 하나의 행으로 압축하지 않는다. 스키마·기존 metadata_copies·큐·파일을 변경하지 않는다. 전체 화면 조회 투영 및 앱 진입점 연결은 아직 남아 있다.

실제 검증:
```text
flutter test --no-pub test/snapshot_download_store_test.dart test/snapshot_receiver_test.dart --reporter expanded
flutter analyze --no-pub lib/core/database/snapshot_download_store.dart lib/core/database/account_store.dart test/snapshot_download_store_test.dart
```
17 통과, 분석 No issues found. 부분 수신 비노출·조회 세대 고정·미존재 구별·UUID 검증·관계 단건 거절·TTL 이후 조회·계정 전환을 실제 임시 SQLite에서 확인했다. 새 테스트가 최초 UUID 오류를 ArgumentError로 잘못 기대해 1회 실패했으며 실제 검증기 계약 FormatException으로 바로잡았다. 거절 검증은 유지했다. 기존 복수 DB 디버그 경고는 기존 테스트의 고의 rollback 테스트에서 발생하며 테스트 실패가 아니다.

로그 .local/workflow/p10-05m-lookup-test.log. 현재 모델 직접 구현 및 별도 코드 검토, 새 에이전트 없음. 인증/계정 범위이므로 높은 추론이 적합하나 실행 모델·속도 변경 관측은 미확인이다. 코드 커밋은 이 제목의 Git history로 식별하며 정확 CI는 후속 통합 SHA로 기록한다. 폰 실기 미수행, 사용자 직접 할 일 없음.

추가 조회 투영: AccountStore.snapshotMetadataView는 기준선과 기존 metadata_copies를 한 트랜잭션에서 함께 반환한다. 서버 자료와 localJson을 자동 병합하지 않으며 기존 송신 기준 revision/basePayload/큐 상태를 변경하지 않는다. snapshot_download_store_test + account_store_test 41 PASS/기존 환경별1 skip, 관련2파일 분석 No issues found. 같은 ID의 서버 메모와 미전송 초안이 각각 보존되고 타 계정에서 모두 보이지 않음을 확인했다. 로그 .local/workflow/p10-05m-view-test.log. 이후 화면 소비와 편집 기준 반영은 별도 검증한다.

통합 e4adb7fc68cc445b05bd6f4fe046d5b5e840a842 필수4 CI PASS: CI36796712600, API contract36796712573, Idempotency MySQL36796712623, Development workflow36796712619.
