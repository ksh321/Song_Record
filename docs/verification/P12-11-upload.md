# P12-11 임시 객체 대조 (원수)

- 원본 계획 p00672~674: 2일 보조 정리, 늦은 PUT 재검사, 임시 공간 512MiB 잠금, 일일 객체 대조. P12-10 최종 SHA 9399296d9b245d1032a8c469b816d66c74365b68 필수 CI 통과 후 측정 finish→begin. 요청·관측 gpt-6.1-sol/medium, 현재 모델 직접 구현·검사·별도 검토.
- UploadObjectInventory/R2Storage: worker 역할에서 페이지 단위 객체 목록과 실제 최종 바이트 확인. 목록 호출/순회 시간 상한. 객체 키·서명 URL·비밀값 로그 미출력.
- UploadInventory: 활성 시도/live lease 보호. 종료 시도는 URL 발급보다 늦은 종료 시각 뒤10분 유예하여 늦은 PUT 반복 정리. 알 수 없는 키는 삭제하지 않고 임시 공간에 포함. 512MiB 이상 또는 불완전 관측 시 새 예약 차단. 기존 예약 재개는 중복 예약이 아니므로 허용.
- 일일 대조: 연결된 STORED/DELETING 세대, 실제 크기/SHA-256, 개인·전체 used/reserved, VERIFYING 작업 연결 확인. 별도 reconciliation 잠금·개수·시각 기록. 운영자 upload_locked·자산·세대·회계를 임의 수정하지 않음. 종료/없는 시도의 미연결 최종 객체만 grace·참조 재확인 후 정리.
- V18 관측/불일치 열과 제약 추가. 초기 단일 worker의 정리1분·대조1일 스케줄 연결. 실제 MySQL 검사는 별도 일회용 fixture로 필수 CI에 연결.
- 일괄 test bootJar r2CheckerClasspath --offline --console=plain: PASS 53초. XML 594개, 실패0·오류0·조건부 건너뜀72개, 실행522개. 로그 .local/workflow/p12-11/final-local.log, 요약 .local/workflow/p12-11/summary.json. 조건부 MySQL 건너뜀은 통과 근거가 아니며 필수 CI 대기.
- 실제 dev.worker 저장 키 audio-check PASS, UTC 2026-10-09T00:55:35.508251Z. 자기 합성 임시/최종 객체 목록·크기·오디오·불변 바이트·삭제/존재 없음 확인. 운영/다른 사용자 데이터 미수정.
- 현재 모델 별도 검토: 활성 검증 보호, 종료 상태 단방향성, 세대 키 재사용 금지, 실패 시 차단, 운영자 잠금 보존, URL 유예, 최종 참조 재확인, 회계 대조. 늦은 PUT·한도·연결 세대 보존·고아 최종 정리·내용 손상/없음·관측 실패/복구 테스트. 기존 예약 재개를 새 예약으로 오인한 테스트를 새 녹음 예약으로 수정했으며 동작 약화 없음.
- 대기 USER-049: 개발/운영 임시 버킷 각각 temporary/ 활성2일 삭제 규칙 실제 확인. 브라우저 초기화 Windows 실행 환경 오류로 직접 조작 안내. infra/r2/temporary-lifecycle.json 예시, 기존 규칙 보존. 폰 개입 알림 서버 접수, 실제 수신 미확인.
- 커밋·푸시·필수 CI·완료 판정 전. P12-12 미착수. 다음: 두 버킷 회신→명시 파일 커밋/푸시→필수 서버·DB CI→finish11/begin12.
- 학습: 객체 목록은 DB 상태를 대체하지 않는다. 수명주기는 보조 안전망이며 활성 작업 보호·늦은 업로드 정리·실제 사용량 대조가 함께 필요하다.

## 실제 수명주기 확인
- 사용자 제공 개발/운영 임시 버킷 사진 각각 temporary/ 접두어, 2일 후 객체 삭제, 사용 중 확인. 기본7일 multipart abort 규칙 유지. USER-049 완료, 직접 할 일0건. 실제 API 조회가 아닌 사용자 화면 확인 근거.

## CI 수정 근거
- P12-11-MIGRATION-COUNT: 실제 MySQL 71개 중1개 실패. V9→최신 업그레이드 실행 개수가 V18 추가로8→9가 됐는데 기대값8 유지. 기대9로 수정, 기존 데이터 보존·Flyway validate·재실행0 검사 유지. 새 객체 대조 MySQL 검사 및 서버 전체 검사 PASS. 원인별 수정1회, 모델 추가 호출/상향 없음.

- 동일 근본 원인 P12-11-MIGRATION-COUNT 두 번째 위치: infra/scripts/verify_p04_migrations.sh 최신 목록 V17까지만 허용하여 V18 후 실패. 전체 저장소 관련 버전 기대 검색 후 최종 목록 V18 포함·설명 갱신. 단계별 V4~V9 기대 및 키 backfill/동일 데이터 재시작 검사는 유지. 실제 MySQL 테스트71개 PASS 및 서버 PASS, 수정 후 최종 전체 필수 CI 재확인. 별도 사용자 행동 없음.
