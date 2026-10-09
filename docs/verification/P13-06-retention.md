# P13-06 객체 삭제 확정 (원수)

- 원본 계획 [p00699]~[p00700], 설계의 삭제/보존/용량 계약, R059·R060·R061·R062·R063·R064 관련 범위 대조. 사용자 지정 Sol6.1/medium 고정, 현재 모델 구현과 별도 검토.
- ASSET_DELETE 작업은 짧은 잠금 스냅샷 → 트랜잭션 밖 R2 HEAD/DELETE/HEAD → 유효 lease로 DB 확정 순서. 404는 버킷 접근 성공도 확인해야 부재로 인정하며 403·네트워크·버킷 오류는 부재로 추정하지 않는다. 삭제 응답 유실 후 HEAD 부재면 확정, 객체가 남거나 결과 불명이면 용량/원장은 유지하며 기존 큐 재시도 정책을 따른다.
- GLOBAL_STORAGE → USER_SYNC → STORAGE_USAGE → RECORDING_ASSET → JOB 잠금 순서. captured owner/recording/generation/hash/key/size와 lease를 확인하고 사용자·전역 used 차감, generation 삭제 원장, asset NONE, cleanup SUCCEEDED, change_log, job 완료가 원자 커밋한다. expired lease·새 generation은 확정하지 않는다. 삭제 전 최신 보호가 바뀌면 STORED 복구/취소. 삭제가 이미 실제 완료된 경우 동일 generation만 최신 revision에 확정하고 다른 metadata/hold를 보존한다.
- worker/스토리지 활성 환경에서 기존 계정 접근·큐 정책으로 삭제 실행기 연결. API 역할은 삭제 실행기 미활성. 검토에서 없는 JobQueue Bean 의존성을 발견하여 기존 방식의 직접 큐 생성으로 수정, 두 역할 구성 시작 검사 PASS(2 tests, 14초; 삭제 장애 검사 포함).
- 기존 retention GET에 선택적 X-Cleanup-Confirmation-Id를 추가해 계정·녹음·generation별 최종 상태 조회. 토큰을 URL에 넣지 않는다. 기존 응답은 헤더 없으면 그대로. 앱은 일회 재조회 훅에서 동일 token/owner/recording/generation의 SUCCEEDED/CANCELLED/EXPIRED만 영속 로컬 fence 해제한다. 시간 경과·응답 유실·중간 상태·불일치 결과는 해제하지 않는다. 이 단계는 코어 연결이며 새 제품 UI/앱 시작 자동 호출 완료로 주장하지 않는다.
- 검사: python .local/workflow/p13-06/check_all.py — 전체 서버 test/bootJar PASS52초, Flutter816 PASS82.8초. 구성 수정 후 영향 범위 서버 test/bootJar PASS14초. analyze/계약/diff 최종 결과 별도 기록.
- 실제 R2: 등록된 dev.worker DPAPI 키를 메모리 → bounded stdin으로 전달, 새 무작위 소유자/녹음/generation 시험 객체에만 write/read/delete/HEAD. 실제 R2 + 격리 H2 원장/용량 확정 PASS(2026-10-09T04:38:28Z). 생성 전 부재 확인, 기존/운영 객체 변경 없음. .local/workflow/p13-06/r2-report.json에 고정 상태만 저장. 실제 MySQL은 로컬 Docker daemon 미실행으로 CI의 일회용 DB 검사 대기.
- 주요 검사: 삭제 응답 유실, 실패 후 재시도, 삭제 후 lease 만료/재개, 새 generation 보호, 신규 보호 취소, 로컬 DB 재개/만료만으로 해제 금지, 정확한 인증 GET/식별자 불일치 거부, R2 403/404/버킷 접근 오류 구분. P13-03 기존 실제 폰6개 PASS 보존, 변경은 서버/코어 자동 검사 대상이라 새 폰 실기 요청 없음.
- 별도 검토: 원본 완료 조건·실제 diff·DB 제약/트리거·락 순서·lease·계정 격리·원장 중복·사용자/전역 used·metadata 보존·R2 역할/typed key·네트워크 트랜잭션 분리·응답/로그 비밀값·로컬 보호 해제 범위 대조. 시작 구성 지적 해결 후 관련 재검사 PASS. 필수 CI 전에는 완료 아님.
- 학습: DELETE 성공/실패 응답은 실제 객체 상태와 다를 수 있다. 물리 상태 확인과 DB 원장/용량 확정을 분리하고 작업 권한으로 최종 커밋을 보호해야 한다.

- 최종 정적/계약: Flutter analyze PASS20.3초, API 계약 PASS2.4초. 전체 diff 검사에서 기존 할 일 파일 EOF 공백 발견, 내용 보존 후 공백만 정리하고 재검사.
