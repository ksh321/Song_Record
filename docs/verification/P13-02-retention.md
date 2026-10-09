# P13-02 정리 후보 계산 (원수)

- 계획 p00686~688, 설계 p00429~437, R058/R060/R093. P13-01 최종 SHA525b2218a9c12940d545b58f87156489372e3a5e 필수 CI PASS 뒤 finish→begin. 요청·관측 gpt-6.1-sol/medium 고정, 같은 대화 직접 구현/검사/별도 검토.
- CleanupCandidates: USER_SYNC 계정 잠금 안에서 실제 최신 녹음 후보·곡 대표·활성 여부로 자동 역할을 계산한다. 아직 비동기 선정 갱신이 도착하지 않았어도 최신 메타정보를 사용한다. 고정 슬롯 current/pending, PENDING_REPLACEMENT 및 다른 보호 사유를 합쳐 무보호 STORED에만 WAITING_LOCAL_CONFIRM을 둔다.
- 미연결 서버 사본에는 ORPHAN_KEEP을 두며 고정 슬롯을 소비하지 않는다. 재연결 후 이 사유 종료의 구체 정책은 P13-09에서 진행하고 그 전에는 보수적으로 유지한다. 보호가 다시 생기면 WAITING_LOCAL_CONFIRM만 제거하고 다른 사유는 유지한다. 이 작업은 삭제 승인·파일 삭제·사용량 차감·로컬 사본 확인이 아니다.
- 기존 V5 테이블 재사용, 새 migration 없음. 60초 주기 100개 커서 순환으로 정리 후보 갱신, 각각 짧은 READ_COMMITTED 트랜잭션. 보호 사유 변경만 asset revision 증가, 같은 계산 반복은 중복/증가 없음. NONE/DELETING 자산이나 비활성/다른 계정은 후보로 만들지 않는다.
- CleanupCandidateDatabaseChecks/Tests 및 실제 MySQL 조건부 검사: 새 자동 역할, 비동기 선정과 무관한 최신 상태, 선정 해제 후 확인 대기, 반복, current/pending 고정, 교체 보호, 미연결 보호와 슬롯0, 다른 계정·비활성·기존 객체 필드/바이트 유지 대조.
- 서버 전체 test/bootJar --offline PASS51초, 전체600/실행525/조건부75/실패0/오류0. 로컬 MySQL 조건부 skip은 통과가 아니며 CI 필수. 로그 .local/workflow/p13-02/local.log, summary.json. 검토 시 테스트 계정 비활성값을 실제 DB의 DELETING으로 맞추고 pending 고정 확인 보강 후 해당 검사+bootJar PASS7초(recheck.log). 제품 제약 완화 없음.
- 별도 현재 모델 검토: 원본 완료 조건·실제 diff·결과·계정 경계·잠금 순서·실제 자동 후보·고정 pending·다른 보호 사유·rev/no-op·페이지 진행·파일 보존 대조. 추가 지적 해결 후 PASS. 이 범위 서버 내부 상태 계산만 변경, 새 폰 실기 필요 없음. 커밋/필수 CI 대기.
- 학습: WAITING_LOCAL_CONFIRM은 삭제 명령이 아니라 마지막 사본을 잃지 않도록 확인을 기다리는 보존 사유다.
