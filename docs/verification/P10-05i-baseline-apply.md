# P10-05i — 일관된 초기 스냅샷: 기준 사본·커서 원자 적용

2026-09-30. 구현계획서 P10-05 ‘일관된 초기 스냅샷’ p00588~589, D09/R040·R041의 하위 실행 범위. 기존 P10-05a~h 기반에서 기준 적용 부분을 P10-05i로 관리한다. 새로운 제품 요구사항/독립 계획 번호를 만든 것이 아니다.

## 구현

- AccountStore.applySnapshotDownload가 실제 전체 검증을 마친 VERIFIED 사본만 APPLIED로 바꾸고 snapshot_baseline pointer와 sync_cursors의 last_change_seq/baseline_complete/resume을 같은 트랜잭션에서 반영한다. 현재 cursor보다 오래된 사본은 거절한다. 최종 계정/만료 fence가 실패하면 상태·pointer·cursor가 모두 rollback된다.
- 이미 적용된 같은 사본의 재요청은 상태/TTL을 바꾸지 않는다. 30분 TTL은 다운로드 기한이며 이미 적용한 로컬 기준 데이터의 사용 기한이 아니다. APPLIED 사본은 미완성 다운로드 폐기에서 제외한다.
- snapshotBaselinePage는 현재 기준 사본을19종 엔터티별로 조회한다. 두 번째 페이지부터 기준 token을 고정해야 하고 다른 세대 token은 거절해 페이지 사이 교체가 섞이지 않는다. 현재 계정의 불변 행만 반환한다.
- local_mutations/metadata_copies의 로컬 편집·이력·녹음 파일은 재작성하지 않는다. 일반 readMetadata의 서버 캐시 투영과 실제 HTTP 수신/UI 연결은 후속 범위다. 이 저장소 기반 구현만으로 앱의 전체 초기 동기화가 작동한다고 보고하지 않는다.

## 검증·검토

```text
flutter test --no-pub test/snapshot_download_store_test.dart --reporter expanded
flutter analyze --no-pub lib/core/database/account_store.dart lib/core/database/snapshot_download_store.dart test/snapshot_download_store_test.dart
flutter test --no-pub test/snapshot_download_store_test.dart test/snapshot_schema_test.dart test/snapshot_response_test.dart test/account_store_test.dart test/canonical_song_store_test.dart --reporter expanded
```

신규/기존 수신9 통과, 분석 No issues found. 최종 영향 통합 **93 통과, Windows 심볼릭 링크 권한1 skip**. 기존 검증 범위를 문서 부족 때문에 반복한 것이 아니라 AccountStore 변경의 편집/매핑/파일 영향 검증이다. 실제 사용자 앱/파일에는 변경하지 않았다.

신규 근거: 검증 전 적용 거절, 적용 후 cursor7과 동일 baseline조회, 미전송 draft 유지, 잘못된 세대/미고정 후속 페이지 거절, TTL 이후 재열기/재적용/폐기 요청에도 기준 유지. 같은 실제 SQLite 연결에서 APPLIED SQL이 수행된 직후 계정 권한 상실을 주입해 pointer/state/cursor rollback을 확인했다. 기존 cursor8에 cursor7 적용은 거절하고 이전 값과 VERIFIED 자료를 보존한다.

현재 모델 별도 코드 검토: D09의 최종 한 트랜잭션 조건, 기존 cursor_no_rewind/FK/불변 트리거, 실제 SQL 수정 표, 계정 fence와 실제 결과를 대조했다. 독립 에이전트 검수 아님. 로그 .local/workflow/p10-05-baseline-test.log, p10-05-baseline-integration.log. 커밋/필수 CI는 후속 기록. 폰 실기 요청 없음, 사용자 확인 대기0건.

다음: 동일 op_id의 접수/서버 생성 상태/페이지 HTTP 수신·중단 재개 연결, 기존 메타데이터 조회 투영 및 앱 흐름 연결. 전체 P10-05 미완료.
