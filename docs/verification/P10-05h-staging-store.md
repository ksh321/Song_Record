# P10-05h — 계정 경계의 영속 수신·재개·완결성 검증

2026-09-30. P10-05/D09/R040·R041. 현재 모델 직접 구현·별도 코드 검토. 새 에이전트 없음.

- AccountStore에 beginSnapshotDownload/snapshotDownloadState/appendSnapshotPage/verifySnapshotDownload/discardSnapshotDownload를 연결했다. 직렬 계정 lease를 유지하고 SnapshotDownloadStore는 각 트랜잭션 내부의 최종 계정/만료 fence를 검사한다.
- 한 페이지의 행과 다음 cursor를 함께 commit한다. 기존 마지막 ordinal과 일치하지 않는 재수신/중복/완료 페이지는 거절하고 일부 행만 남기지 않는다. manifest는 재수신 시 동일 값만 인정한다. canonical UTF-8 합계100MiB 제한을 검사한다.
- 재시작 후 manifest·19종 progress를 읽어 재개한다. 전체 완료 표식/개수가 맞아야 모든 저장 행을100개씩 읽어 소유권/리소스/순서/해시/만료를 다시 검증하고 VERIFIED로 바꾼다. 현재 기준 pointer/화면 데이터/cursor는 아직 바꾸지 않는다.
- 만료/실패한 미적용 다운로드 폐기는 파생 자료만 삭제한다. APPLIED는 제외하며 기존 미전송 변경·파일 표를 수정하지 않는다. 다른 계정과 오래된 AccountStore handle은 읽기/쓰기를 거절한다.

실행:

```text
flutter test --no-pub test/snapshot_download_store_test.dart test/snapshot_response_test.dart test/account_store_test.dart --reporter expanded
flutter analyze --no-pub lib/core/database/snapshot_download_store.dart lib/core/database/account_store.dart lib/core/sync/snapshot_response.dart test/snapshot_download_store_test.dart
```

**42 통과, Windows 심볼릭 링크 권한1 skip, 분석 No issues found.** 신규 store6/wire8와 기존 AccountStore 영향 범위. 최초 신규14 통과 후 폐기 시 실제 미전송 편집 보존 assertion을 추가해 위 통합을 실행했다. 단순 중괄호 분석 지적1개 수정. fixture DB가 서로 다른 executor인 경고를 데이터 경쟁 근거로 사용하지 않으며 경고를 전역 비활성화하지 않았다.

실제 결과: 닫기/재열기 후19종 재개→VERIFIED, 미전송 private draft/기존 cursor 유지, 중복 거절, 모든 페이지를 바꿔도 manifest hash 불일치로 상태 승격 차단, 만료 폐기 후 편집 유지, 계정 전환 거절, 마지막 lease 검사 실패 시 실제 삽입 행/progress 동시 rollback. 폰 실기/설치 완료로 확대하지 않는다.

현재 모델 검토: 네트워크/DB 행 모두 같은 검증 생성자를 거치고, 저장 코드가 원본 업무/파일 표를 갱신하지 않는지 실제 SQL과 비교했다. 최종 commit 직전 계정/시간 재확인을 유지한다. 필수 hash/count 검증을 상태 표식만으로 대체하지 않는다.

로그 .local/workflow/p10-05-staging-store-test.log, p10-05-staging-store-integration.log. 커밋/정확 SHA CI는 후속 기록. 다음은 검증 완료 사본의 기준 pointer/cursor 원자 적용과 실제 HTTP 수신 연결. 전체 P10-05 미완료, 사용자 확인 대기0건.

코드 커밋 c1b9a4c는 새 한글 커밋 지시 전에 생성했다. 운영 문서 커밋95a2079와 함께 일반 push했으며 검증 대상 통합 HEAD는95a2079다. 이 대상의 필수 CI 확인 대기이며 c1b9a4c 자체에 별도 CI가 실행됐다고 기록하지 않는다.
