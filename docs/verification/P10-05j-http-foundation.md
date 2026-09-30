# P10-05j — 일관된 초기 스냅샷: HTTP 요청·재개 저장 기반

2026-09-30. 계획서 P10-05 ‘일관된 초기 스냅샷’ p00588~589, D09/R040·R041의 세부 실행 범위로 등록한다. 선행 a~i의 서버/검증/영속 수신 기반을 연결하기 위한 작업이다.

## 구현과 범위

- `snapshot_transport.dart`: 생성·상태·페이지 요청 경로를 코드에서 고정한다. 서버가 준 임의 URL로 자격 증명을 보내지 않는다. HTTPS 또는 명시한 로컬 개발 HTTP만 허용한다. 생성에는 고정 schema_version=1과 호출자가 보존한 operation ID를 사용한다.
- 리다이렉트·자동 재시도 없이 한 번 요청한다. 401/403을 그대로 상위 실행기에 전달하고 네트워크 실패에는 관측한 상태만 남긴다. 시간/응답 크기 제한과 연결 전후·결과 반환 전 계정 fence를 둔다. 페이지는 원문 canonical_payload와 parsed payload를 함께 포함하므로 50행에 맞는 유한 응답 상한을 사용한다.
- `AccountStore.compareAndSetSnapshotResume`: 읽은 재개 문자열과 현재 값이 일치할 때만 트랜잭션으로 갱신한다. 재시작 후 같은 op_id를 보존하고 늦은 응답이 진행된 상태나 해제된 상태를 덮어쓰지 못하게 한다. 최종 계정 fence 유지. 기존 generic resume API와 스키마는 보존했다.
- 아직 HTTP 실행기·자동 상태 전이·화면에 연결하지 않았다. 이 함수만으로 모든 실행 경합이 해결됐다고 판단하지 않는다. 실행기는 요청 직렬화와 동일 계정/동일 회차 조건을 함께 적용해야 한다. 기존 메타데이터 조회 투영도 후속 범위다.

## 실제 검증과 현재 모델 검토

```text
flutter test --no-pub test/account_store_test.dart --reporter expanded
flutter test --no-pub test/snapshot_transport_test.dart test/snapshot_download_store_test.dart test/account_store_test.dart --reporter expanded
flutter test --no-pub test/snapshot_transport_test.dart --reporter expanded
flutter analyze --no-pub lib/core/sync/snapshot_transport.dart lib/core/database/account_store.dart test/snapshot_transport_test.dart test/account_store_test.dart
git diff --check
```

계정 저장29 통과/기존 Windows 링크 권한1 skip. 통합42 통과/동일1 skip. 검토 후 403과 응답 본문 지연 timeout을 추가한 HTTP 최종5 통과. 분석 No issues found, 공백 검사 통과. 처음 HTTP 테스트의 UUID 예외 예상1건을 실제 기존 UuidValue의 FormatException 계약과 일치시켰다. 분석 권고1건은 null-aware map element 문법으로 보완했다. 테스트 삭제·약화나 CI 변경 없음.

현재 모델 별도 검토는 D09 재시도 계약·계정 경계·실제 요청 수·상태 보존 SQL을 대조했다. 독립 검수자 아님. 합성 서버/임시 계정 DB만 사용했으며 사용자 로그인·실기·실제 서버 배포 결과가 아니다. 로그는 .local/workflow/p10-05-resume-cas-test.log, p10-05-http-foundation-test.log, p10-05-transport-final.log.

커밋/정확 SHA 필수 CI는 후속 기록. 사용자 확인 대기0건. 다음은 같은 op_id의 bounded 수신 실행기, READY manifest·페이지 재개·검증·원자 적용 연결, 기존 조회 투영 및 앱 흐름이다. 전체 P10-05 미완료.
