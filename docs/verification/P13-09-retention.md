# P13-09 미연결 보존 처리 (원수)

- 원본 계획 [p00707]~[p00709], 설계 [p00549]~[p00551], R064/R093 대조. 사용자 지정 gpt-6.1-sol/medium 고정, 현재 모델 직접 구현·별도 검토.
- CleanupCandidates는 미연결 STORED에 ORPHAN_KEEP을 유지하며 슬롯을 추가하지 않는다. 재연결 후 현재 자동 선정 또는 current/pending 고정이 실제 보호할 때만 ORPHAN_KEEP을 제거한다. 보호가 없으면 예외 보존은 유지하고 기존 유효한 로컬 보존/명시 손실 확인→삭제 직전 재검사→객체 부재 검증 경로를 통해서만 정리할 수 있다.
- 새 보호가 없다는 이유로 사본 삭제·used 차감·새 고정 슬롯 생성은 하지 않는다. 다른 PENDING_REPLACEMENT 사유도 유지한다. 최신 메타데이터를 USER_SYNC/ASSET 잠금으로 대조하고 이유 변화 때 정책 revision을 올려 과거 확인과 분리한다. 기존 RecordingLinking의 연결 변경 버전 펜스와 주기 재계산 연결을 대조했다.
- 변경: CleanupCandidates와 동일 H2/실제 MySQL 공유 CleanupCandidateDatabaseChecks. 재연결 후 선정 제외·보존 유지, 새 고정 보호 이관, 고정 해제 후 확인 후보·파일 유지, 새 대표 자동 보호 이관, 반복 주기 idempotency, 다른 계정 및 삭제 중 계정 확인. 기존 CleanupAuthorization/Confirmation 검사는 ORPHAN+WAITING 정리의 유효 확인·세대·토큰·필수 보호 조건을 검증한다.
- 검사: 전체 서버 test/bootJar PASS95초. 실제 MySQL은 로컬 환경 skip이며 최종 CI 필수. 별도 현재 모델 검토: 원본 예외 제거 조건, 실제 diff/결과, 동기·revision·계정 경계, 사본/해시/세대/size 불변, 다른 hold 보존 및 자동 삭제 경로 부재 대조. 추가 사용자 행동 없음. 서버 도메인 변경이며 후속 미연결 UI/곡 삭제 전체 기능은 P18/P20 범위다.
- 학습: ORPHAN_KEEP은 고정 자리를 차지하지 않는 사본 보존 사유다. 재연결은 그 사유를 무조건 없애는 동작이 아니며, 새 보호나 확인된 안전 정리로 이관해야 한다.
