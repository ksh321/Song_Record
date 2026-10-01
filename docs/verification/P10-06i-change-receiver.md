# P10-06i — 증분 변경 수신: 한 페이지 수신 제어

2026-10-01. 원본 P10-06 p00590~592, R040의 내용/커서 원자성 및 기존 인증 차단/계정 격리 기준에 따른 세부 작업이다.

ChangeFeedReceiver는 AccountStore에서 계정별 적용 사본 토큰과 현재 커서를 한 트랜잭션으로 읽고, 한 번에 한 페이지를 요청한다. 동시 호출은 같은 실행을 공유하며 타이머/자동 후속 요청을 만들지 않는다. 성공 응답만 기존 검증/적용기를 통과시켜 내용과 커서를 함께 확정한다. 네트워크 전후와 저장 트랜잭션 내부에서 현재 세션을 확인한다.

401/403 및 해당 헤더 뒤 전송 실패는 인증 차단을 유지한다. 인증 확인 뒤 호출자가 명시적으로 해제해야 재개된다. 429/서버 오류/전송 오류는 재시도 가능 상태를 반환한다. CURSOR_EXPIRED는 별도 상태이며 데이터·큐·사본을 자동 삭제하거나 초기화하지 않는다. 잘못된 응답과 미구현 적용 종류는 실패로 남기며 커서를 넘기지 않는다. 현재 앱 화면/스케줄러에 자동 연결하기 전의 수신 제어 기반이다.

변경 파일: apps/mobile/lib/core/sync/change_feed_receiver.dart, apps/mobile/lib/core/database/account_store.dart, change_feed_store.dart, apps/mobile/test/change_feed_receiver_test.dart.

실제 검증:
- flutter test --no-pub test/change_feed_receiver_test.dart test/change_feed_store_test.dart test/snapshot_download_store_test.dart --reporter expanded: **37 PASS**.
- 변경4파일 flutter analyze --no-pub: **No issues found**.
- 실제 격리 AccountStore와 검증된 공유 초기 사본을 이용했다. 신규10개 시나리오: 초기 사본 선행, 성공/재개 커서, 50행 후 다음 페이지 수동 접수, 동시 호출, 지연401/403, 403헤더 후 전송 실패, 만료 커서 보존, 재시도/잘못된 응답, 대기 중 세션 변경.
- 최초 테스트에서 recoveryData의 생성 시각까지 동일 비교해 실패했다. 저장된 전체 tables 비교로 수정해 데이터 보존 검사는 유지했다. 빈 목록 타입 분석 경고도 명시 타입으로 수정했다. 잘못된 로그 상대경로와 PowerShell 파일 쓰기 오류는 코드 검증 실패와 분리했고 올바른 작업 경로/파일 수정 도구로 보완했다. 최종 테스트 로그 .local/workflow/p10-06i-final.log.

현재 모델 검토: 실제 토큰/커서 단일 읽기, 응답 원점 일치, 내부 트랜잭션 세션 확인, 인증 차단 유지, 추가 요청 없음, 저장 실패 시 커서 보존을 대조했다. 원본 요구사항·실제 diff·테스트 결과를 대조한 현재 모델 검토이며 독립 에이전트 검수가 아니다. 모델/속도 적용값 미확인 상태 유지.

남은 범위: 삭제 원장·관계/asset 전용 적용, 만료 커서 재동기화(P10-08), 기존 스케줄러/앱 연결과 그 변경의 검증. 전체 P10-06 완료/새 폰 테스트 완료로 표시하지 않는다. 커밋은 Git history, 필수 CI는 후속 정확 SHA 기록을 따른다.
