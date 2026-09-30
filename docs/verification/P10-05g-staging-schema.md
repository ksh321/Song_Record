# P10-05g — 로컬 v5 수신 저장 영역·비파괴 이관

2026-09-30. P10-05/D09: 부분 수신과 현재 기준 데이터를 분리하고 재개 지점을 영속 보관하는 기반. 현재 모델 직접 구현·별도 코드 검토, 새 작업자/검수자 없음.

## 변경

- local_schema.drift에 snapshot_downloads/rows/progress/baseline 4개 표 추가. 계정 FK, 사본·엔터티·ordinal 키, 정확한 canonical JSON 원문, 받은 마지막 ordinal/다음 cursor, 고정 manifest를 보관한다. 기존 metadata_copies·local_mutations·파일·별칭·보존 증거 표는 재작성하지 않는다.
- 계정/manifest 불변, RECEIVING→VERIFIED→APPLIED 순서, 받은 행 교체/수정 방지, 검증된 행 직접 삭제 방지, 진행 지점 후퇴/교체 방지, APPLIED만 기준 사본 지정, 현재 기준의 부모 사본 삭제 방지 제약. DB의 상태만으로 해시 검증 완료라고 판단하지 않으며 후속 저장 서비스가 실제 검증 후 전이한다.
- AccountDatabase v1~v4→v5 명시 이관. 기존 v4 이관은 from<4에서만 실행하고 추가 표/트리거만 생성한다. 지원하지 않는 미래 버전은 거절하며 재생성하지 않는다. 기존 drift_schema_v1~v4는 보존하고 v5와 생성 코드/steps를 추가했다.
- 복구 내보내기에 신규 표4개를 포함. user schema_version=5를 실제 값으로 반영하고 포맷 version2는 유지. 이전 미전송/파일 보존 assertion은 그대로 유지한다.

## 실제 검증

```text
dart run build_runner build
dart run drift_dev make-migrations --no-test
flutter test --no-pub test/snapshot_schema_test.dart test/canonical_schema_test.dart test/account_store_test.dart test/canonical_song_store_test.dart --reporter expanded
flutter analyze --no-pub lib/core/database test/snapshot_schema_test.dart test/canonical_schema_test.dart test/account_store_test.dart
```

최종 **82 통과, 1 skip**, 분석 No issues found. Windows 심볼릭 링크 권한이 없어 기존 링크 격리 테스트1개가 skip됐으며 통과로 기록하지 않는다. Linux 필수 CI에서 해당 검증을 유지한다. 기존 v1~v3 이관 검증을 유지하고 v4 fixture를 추가해 기존 모든 표의 행·요청 순서·wire·재시도 예산·커서·합성 파일 보존을 대조했다. 새6개 검증은 계정 격리, 불변/상태/기준 FK, progress NULL cursor/후퇴 차단, 파생 수신 영역만 폐기, 파일 DB 재개, 페이지 트랜잭션 중단 rollback을 확인한다.

이번 작업에서 만든 미커밋 v5 초안이 최종 SQL과 달라 drift_dev가 재생성을 거절했다. 해당 초안 파일만 .local/workflow/staging-v5-first-draft.json으로 옮겨 보존하고 최종 v5를 생성했다. 기존 버전 스냅샷·실제 사용자 DB는 삭제/교체하지 않았다. 분석의 단순 따옴표 지적1개 보완. 제품 이관 테스트 실패는 없었다.

현재 모델 검토: 사용자 검증된 기존 범위를 되돌리지 않고 신규 추가만 이관하는지, FK/NULL CHECK의 SQLite 의미, OR REPLACE 우회 차단, 동일 계정 기준 pointer, 실제 rollback·재개 결과를 확인했다. 대량 generated diff는 신규 FK 관계 코드 생성 결과다. 신규 스키마로 실제 폰 앱을 설치/이관했다고 기록하지 않는다.

로그 .local/workflow/p10-05-staging-codegen.log, p10-05-staging-schema-test.log, p10-05-staging-integration.log. 로컬 검증 완료; 커밋/정확 SHA CI는 후속 기록. 다음은 AccountStore 경계의 페이지 원자 저장·재개·전체 hash 확인 후 기준/커서 원자 적용. 사용자 확인 대기0건. 전체 P10-05 미완료.
