# P10-05o — 일관된 초기 스냅샷: 녹음 관계 조회

2026-10-01. 원본 계획 P10-05 p00587~589, D09 및 SnapshotSourceRows의 RECORDING/RECORDING_FILE_SPEC/RECORDING_TAG 구성을 대조한 후속 세부 작업이다.

SnapshotDownloadStore.recordingBaseline과 AccountStore.snapshotRecordingBaseline은 적용된 초기 사본의 녹음·파일 명세·반복 태그 행을 같은 계정/토큰/읽기 트랜잭션에서 조회한다. 태그가 같은 recording_id를 공유해도 각 행과 당시 이름을 보존한다. 기준 사본 없음과 사본 안에 녹음 없음은 구분하며, 고아 관계·중복 태그·중복 파일 명세·다른 토큰/계정은 거절한다. 적용된 사본 조회는 다운로드 TTL과 분리한다. 반환 태그 목록은 불변이며 payload는 분리된 사본이다.

변경 파일: apps/mobile/lib/core/database/account_store.dart, snapshot_download_store.dart 및 apps/mobile/test/snapshot_recording_baseline_test.dart.

실제 검증:
- flutter test --no-pub test/snapshot_recording_baseline_test.dart test/snapshot_download_store_test.dart test/change_feed_store_test.dart --reporter expanded: 30 PASS.
- 위 변경3파일 flutter analyze --no-pub: No issues found.
- 새 조회 테스트5개는 격리 메모리 SQLite의 적용 상태 자료로 조회 경계와 관계 보존을 검증한다. 네트워크 전체 수신이나 휴대폰 실기로 확대하지 않는다. 로그: .local/workflow/p10-05o-recording-baseline.log.

현재 모델 코드 검토에서 원본 관계 키, 계정/토큰 필터, 단일 트랜잭션 및 최종 계정 확인, 반복 행 보존, 쓰기 부재를 재대조했다. DB 버전·큐·커서·파일·기존 사용자 데이터는 변경하지 않는다. 모델/속도 변경이나 독립 에이전트 검수라고 주장하지 않는다.

남은 일: 이 관계 조회를 초기 업무 사본 투영 및 증분 적용에 연결한다. 현재 읽기 기반만 구현했으며 전체 P10-05 완료가 아니다. 설치된 e4adb7f APK와 USER-024 결과 범위에 새 코드를 포함하지 않는다. 대상 커밋은 Git history, 정확 SHA CI는 후속 진행 기록에 남긴다.

## 2026-10-07 P10-05 변경 코드 직접 검토

- 검토 대상: `cd0b6da..9f499baa75a262f11f4c7c3d9c727df1ba7466be`. 현재 에이전트 직접 정적 검토이며 별도 모델 호출·Worker/Reviewer·자동 실행기 재개 없음. 검토 시작 시 작업 트리 깨끗함.
- 결과: 이번 제품 변경으로 새로 발생한 수정 필수 결함을 발견하지 못했다. D09의 staging 검증 후 원자 적용 계약, 계정 직렬화/lease, 초기 완료 분기와 기존 사본 복구, 증분 호출 경계를 대조했다.
- `_initialMetadata` 이후 공통 메서드는 기존 ChangeFeedStore와 메서드 이름·공백을 정규화한 코드 비교가 일치했다. SnapshotBusinessStore 적용은 바깥 publication 트랜잭션 안에서 실행되며 최종 만료/lease 검사 실패 시 업무 사본·포인터·커서 변경이 함께 롤백되는 구조다. 이미 적용된 사본은 TTL을 다시 요구하거나 진행된 커서를 되감지 않는다.
- 미전송 큐/고정 wire/재시도 예산/canonical hold/충돌 해결 원장/개인 입력 보존 조건, 다중 페이지·재개방·증분 실패·SQL/lease/만료 실패·등록 합성 녹음 파일 및 저널 검사를 대조했다. 기존 검사를 삭제하거나 보호 조건을 제거한 변경 없음. 초기 적용 후 조회 기대값과 resync의 기존 곡 PATCH 준비 수정은 새 동작 계약에 부합한다.
- 실행 근거: 사용자가 이 대화에서 초기 관련 검사, resync 2개, receive-regression·preservation-regression·analyze, 원본 정합성·diff 검사 통과를 보고했다. 이번 검토에서 테스트를 재실행하지 않았고 독립 재실행 결과로 표현하지 않는다. 대상 커밋 범위 `git diff --check`는 직접 종료0 확인했다.
- 남은 단계: 원격 푸시 여부 및 대상 SHA의 필요한 CI 확인. 제품 전체 완료나 P10-06 착수로 처리하지 않는다. USER-035는 실행기 원인 비교 형식 오류에서 생성된 과거 요청이며 실제 로그인/사용자 조작 필요의 근거가 아니다. 자동 실행기 상태 복구는 이번 제품 정적 검토 범위에 포함하지 않았다.

## 2026-10-07 P10-05 수동 완료 근거 대조 및 실행기 재개

사용자 로컬 검사 통과 확인과 위 직접 코드 검토에 더해, 대상 `9f499baa75a262f11f4c7c3d9c727df1ba7466be`의 필수 [CI 37552635532](https://github.com/ksh321/Song_Record/actions/runs/37552635532) PASS를 직접 확인했다. 원격 추적 reflog의 직전 push `cd0b6da1f3c14e081613df7bd38f0974ad79d91e`를 BaseCommit으로 사용해 github-check.ps1 종료0/Overall PASS를 확인했다. API contract·Idempotency MySQL·Development workflow는 NOT_APPLICABLE이며 통과 실적으로 세지 않는다. 기존 계획의 새 실기 불필요 판단을 유지한다. P10-05-NEXT 완료, 기존 세부 ID·완료 이력 보존.

이 판정은 사용자 수동 검증·커밋 이후의 외부 완료 근거 대조다. 과거 실행기의 실패 로그를 PASS로 바꾸거나 새 REVIEW 호출이 있었다고 기록하지 않는다. 기존 체크포인트 전문은 로컬 P10-05-before-manual-completion-reconciliation.json에 보존하고 실패 원인 이력은 유지한다. USER-035는 원인 비교 형식 오류에서 생성된 불필요한 요청으로 AI가 종료했다. 사용자 승인 종료 번호는 P10-06이며 이후 번호는 시작하지 않는다.
