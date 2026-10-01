# P10-08a — 만료 커서 재동기화: 보존 요청 저장 기반

2026-10-01. 원본 P10-08 p00596~598와 R041의 미전송 변경/파일 보존, D09 초기 사본 계약에 따른 세부 컴포넌트다. 전체 P10-06 완료를 가정하지 않는다. 선행은 f037311 필수 CI4에서 검증된 계정 저장/초기 수신 및 증분 제어 기반이며, 전체 P10-08-NEXT의 기존 선행은 그대로 유지한다.

AccountStore.requestSnapshotRefresh는 관측한 적용 사본 토큰·커서와 현재 상태가 같을 때만 REQUESTED/op_id를 저장한다. baseline_complete를0으로 내려 새 변경 수신을 막지만 이전 토큰·커서·사본·업무 사본·미전송 큐·파일은 지우지 않는다. 기존 사본은 읽을 수 있다. 요청과 flag는 한 SQLite 트랜잭션이며 다른 계정/이미 시작된 요청/더 최신 커서로 바뀌었다면 덮어쓰지 않는다. 새 사본 검증/적용 성공 때만 기존 apply가 기준 사본과 커서를 교체한다.

코드 검토에서 재다운로드가 만료되어 resume이 정리돼도 이전 baseline 포인터만 보고 완료 처리하지 않도록 baseline_complete=0 유지가 필요함을 확인했다. 앱 재시작 후 요청 UUID가 유지되고 같은 요청으로 이어진다. 외부 DB/볼륨 삭제 또는 실제 파일 삭제는 없다.

실제 검증:
- flutter test --no-pub test/snapshot_download_store_test.dart test/snapshot_receiver_test.dart test/change_feed_receiver_test.dart --reporter expanded **31 PASS**.
- 변경2파일 analyze **No issues found**. 테스트 반복문의 중괄호 권고1개를 보완 후 재확인했다.
- 실제 임시 AccountStore에서 미전송 변경과 합성4바이트 파일을 준비했다. 재요청/계정 재열기 후 sync_cursors를 제외한 모든 테이블 동일, 파일 동일, 옛 사본 읽기 유지, 오래된 토큰/커서 거절, 동시 요청1개만 접수, 만료 정리 후에도 완료flag0 유지를 확인했다.
- 로그 .local/workflow/p10-08a-test.log. 현재 모델이 요구사항·CAS 조건·계정 fence·트랜잭션·실제 결과를 검토했다.

아직 CURSOR_EXPIRED 응답이나 앱 실행 제어에 자동 연결하지 않았다. 전체 P10-08 완료 아님. 사용자 USER-025 대상 c7df3fd APK에 이 코드는 없으며 테스트 요청 대상은 유지한다. 정확 SHA CI는 후속 통합 기록을 따른다.
