# P25-06 감시 프로그램 검정 창 수정

사용자 docker.exe 검정 창 반복 표시 보고에 대한 환경 수정이다. 베타 실제 로그인/배포 완료 근거와 구분한다.

- 실제 프로세스 조회에서 backup_ledger_runtime 감시 Python PID11384가 docker.exe PID27540의 부모이고 Docker 자식 conhost가 확인됐다. 감시 부모는 CREATE_NO_WINDOW/DETACHED_PROCESS로 시작하지만 validation_runtime.run의 자식 subprocess에는 창 숨김 플래그가 없었다. 원장 점검은 정상시30초, ACK 대기시5초 간격이다. 창 반복 표시만으로 Docker/DB 실패라 판단하지 않는다.
- validation_runtime의 일반 명령/볼륨 조회와 backup_runtime의 제한 출력/DB 잠금 명령에 CREATE_NO_WINDOW를 적용했다. 기존 명령 인수·표준 입력 비밀 주입·출력 제한·타임아웃·실패 판정은 유지한다. Windows 이외에서는 플래그0으로 동작한다. 비용/운영 폰 알림 자식 PowerShell에도 같은 설정 적용.
- 원래 명령줄은 출력하지 않고 이 저장소의 정확 스크립트 경로와 watch 인수·현재 PID를 메모리에서 대조했다. 공유 백업 실행 잠금을 획득한 경계에서 확인된 감시4개만 재시작했다. 데이터베이스/컨테이너/API·worker 재생성·키 변경·AI 추가 호출 없음.
- 재시작 후 감시 각각1개: cost14096, operations29192, backup27924, backup-ledger26656. 감시 상태 파일의 PASS 및 시각만 조회했다. 기존 일일 백업 PASS는 이전 실행이며 새 백업 실행으로 세지 않는다. 전체 출시 준비 판정과 별개다.
- 관련 검사: bundled Python에서 tools/tests 경로를 PYTHONPATH에 넣어 validation_runtime/backup_runtime/cost_monitor/operational_checks/backup_ledger unittest 합계30 PASS. 최초 모듈 방식 호출은 test_backup_ledger의 이웃 fixture 모듈 검색 실패였으며 올바른 기존 테스트 경로로 재실행했다. 테스트 삭제/약화 없음.
- 현재 모델 별도 검토: 실행 인수/입력/출력·오류 처리·비밀 보호·Linux 이식성·백업 잠금/제한 유지 확인. 도구만 변경된 범위의 원격 제품 CI는 정책상 불필요. APK 콜백 변경은 별도 앱 검사/필요 CI 대상이다.
