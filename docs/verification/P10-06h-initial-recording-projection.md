# P10-06h — 증분 변경 수신: 초기 녹음 관계 보존 연결

2026-10-01. 원본 P10-06 p00590~592, P10-05 초기 사본, D09 및 실제 SnapshotSourceRows/RecordingDrafts·Saving·Editing 응답의 차이를 대조한 후속 세부 작업이다.

snapshot_recording_projection.dart는 초기 녹음·파일 명세·태그 행을 검증된 업무 payload로 변환한다. ChangeFeedStore의 기존 SQLite 트랜잭션 안에서 초기 사본→더 최신 캐시→수신 응답 순으로 생략된 부가 정보만 보존한다. 명시된 null/빈 태그는 적용하며 이후 생략 응답으로 옛 태그를 복원하지 않는다. 잘못된 초기 명세는 페이지 전체와 커서를 함께 롤백한다. 원본 snapshot 행은 수정하지 않으며 삭제/관계 이력 필드를 업무 DTO에 끼워 넣지 않는다.

변경 파일: apps/mobile/lib/core/database/change_feed_store.dart, snapshot_recording_projection.dart, apps/mobile/test/change_feed_store_test.dart.

실제 검증:
- flutter test --no-pub test/change_feed_store_test.dart test/snapshot_recording_baseline_test.dart test/recording_change_projection_test.dart test/snapshot_download_store_test.dart --reporter expanded: **36 PASS**.
- 변경3파일 flutter analyze --no-pub: **No issues found**.
- 최초 관련24 PASS 후 검토에서 명시 빈 태그/null 등급→후속 생략 응답까지 회귀를 확장해 위36개를 실행했다. 전체 원본 snapshot 행 동일성과 파일 명세 보존, 잘못된 초기 파일 시 앞선 다른 엔터티까지 롤백을 실제 SQLite에서 확인했다. 테스트는 합성 자료만 사용했다. 로그 .local/workflow/p10-06h-final.log.

현재 모델은 원본 서버 열 목록, 계정/토큰 경계, 최신 revision 우선, immutable 파일 명세, 명시 삭제와 생략 구분, 커서/내용 원자성을 다시 검토했다. 관련 기존 테스트를 약화하지 않았다. 독립 검수 에이전트 사용/모델 설정 변경 주장 없음.

전체 P10-06 미완료: 삭제 원장·관계/asset 전용 적용과 수신기/앱 연결이 남았다. 이 변경은 설치된 e4adb7f APK 및 USER-024 확인에 포함되지 않는다. 코드 커밋은 Git history로 식별하고 정확 SHA CI는 후속 진행 기록에서 확인한다.
