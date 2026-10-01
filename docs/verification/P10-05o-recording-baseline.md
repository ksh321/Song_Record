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
