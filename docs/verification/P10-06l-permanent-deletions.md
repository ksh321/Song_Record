# P10-06l — 증분 변경 수신: 초기 영구 삭제 표식 반영

2026-10-01. 원본 R041/p00312·p00561 및 계획 P10-06 p00591, V6 deletion_ledger, SnapshotSourceRows를 대조한 세부 작업.

초기 사본 원장에서 현재 구현된 SONG/RECORDING/TAG의 계정·대상 UUID·타입·revision·삭제 시각·세대 없음 조건을 검증한다. 원장의 id와 삭제 대상 entity_id를 혼동하지 않는다. 증분 적용 트랜잭션 안에서 최소 삭제 표식으로 metadata_copies를 갱신하고 tombstone을 설정한다. 오래된 변경으로 부활하지 않으며 원장보다 높은 변경/캐시 revision은 임의 해결 없이 롤백한다. 관계/asset 세대 전용 처리가 없는 타입은 여전히 거절한다.

현재 모델 검토 중 빈 증분 페이지에도 초기 삭제 UUID가 반영돼야 함을 확인해 모든 초기 표식을 먼저 적용하도록 보완했다. 기존 영구 원장과 snapshot 행은 유지하며 실제 파일 삭제가 없다. 로컬 초안/미승인 큐/매핑 보류의 보존은 기존 SQL 조건을 공통 _writeCopy로 유지했다. 전체 P10-09 삭제된 대상 관계 처리나 목록/asset 전용 처리는 완료가 아니다.

실제 검증:
- flutter test --no-pub test/permanent_deletion_test.dart test/change_feed_store_test.dart test/change_feed_receiver_test.dart test/snapshot_download_store_test.dart --reporter expanded: **42 PASS**.
- 변경4파일 analyze: **No issues found**.
- 이전39 PASS 뒤 계정/세대 경계 및 빈 응답 회귀를 추가해 최종42개를 실행했다. 잘못된 날짜 원장은 앞선 쓰기와 커서를 롤백, 정상 표식은 미전송 초안/원본 snapshot을 보존, 빈 페이지에도 표식을 저장, 더 높은 revision은 부활 대신 거절을 확인했다. 실제 데이터는 아닌 격리 합성 SQLite 자료를 사용했다.
- 로그 .local/workflow/p10-06l-complete.log. 최초 분석의 import 정렬/중괄호 지적을 보완했다.

현재 모델이 원본 열과 삭제 정책, 실제 diff, 검증 결과, 페이지/표식/커서 단일 트랜잭션을 검토했다. 별도 에이전트 사용 없음. 설치된 c7df3fd와 USER-025는 l 이전 코드이며 이 결과를 새 폰 검증에 확대하지 않는다. 정확 SHA CI는 후속 통합 기록을 따른다.
