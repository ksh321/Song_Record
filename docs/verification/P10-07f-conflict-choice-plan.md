# P10-07f — 충돌 항목의 명시 선택과 새 요청 초안

2026-10-01. 원본 plan.txt P10-07(p00593~p00595), design.txt의 3방향 비교 정책을 P10-07a~c 어댑터에 연결한다. 현재 모델 직접 구현/코드 검토.

- 충돌한 필드만 빠짐없이 LOCAL/SERVER를 지정해야 한다. 결합 필드(키와 이동 값, 녹음 시각과 시간대)는 같은 쪽을 선택해야 한다. 시각이 늦다는 이유로 자동 승자를 고르지 않는다.
- 서버 선택은 해당 로컬 덮어쓰기를 새 요청에서 제외하되 선택 기록을 남긴다. 다른 안전한 수정은 유지한다. 전부 서버와 같으면 새 요청이 필요 없는 명시 결과를 만든다.
- 새 초안은 응답 서버 revision을 기준으로 만들고 합쳐진 도메인 값/지원된 실제 요청 경로를 다시 확인한다. 기존 op_id/시도/payload를 고치거나 직접 전송하지 않는다. 반환값은 불변 JSON이고 toString은 정보를 가린다.
- 실제 계정 트랜잭션은 후속이며, 그 시점의 최신 사본·보류·원본 일치와 새 op_id를 다시 검사해야 한다. 초안 생성 성공은 충돌 해결 완료가 아니다.

## 검증

- 관련 3파일 최초 실행: 기존 비교27 PASS, 새 테스트는 공유 fixture 함수 인자 오류로 로드 실패. 올바른 RecordingEdited 계약을 사용하도록 수정했다.
- `flutter test --no-pub test/conflict_resolution_plan_test.dart`: **9 PASS**.
- `dart analyze lib/core/sync/conflict_resolution_plan.dart test/conflict_resolution_plan_test.dart`: **No issues found**.
- 현재 모델 검토: 선택 누락/여분/결합 불일치 거절, 안전 필드 유지, 정수 기준, 삭제 대상 거절, 녹음 시각 전체 그룹, 원본/선택 입력 보존 및 새 기준 확인.
- 로그 `.local/workflow/p10-07f-test.log`, `p10-07f-recheck.log`. 폰 실기 미수행; 기존 USER-025 확인 범위를 확대하지 않음. 커밋은 Git 이력으로 확인하고 필수 CI는 후속 기록.
