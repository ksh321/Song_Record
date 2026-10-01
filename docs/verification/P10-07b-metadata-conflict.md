# P10-07b — 곡·태그 revision 충돌 비교 어댑터

2026-10-01. P10-07 3방향 충돌 처리의 독립 하위 작업. 원본 design p00300~305 / plan p00593~595. P10-07a 비교기를 실제 저장된 QueuedMutation의 기준·PATCH·409 자료에 연결한다. 아직 dispatcher/자동 재전송/UI에 연결하지 않는다.

## 구현과 검토

`metadata_conflict.dart`는 CONFLICT/PATCH/REVISION_CONFLICT/409이며 기준과 현재값이 있는 SONG·TAG만 비교한다. 도메인 스냅샷 검증, 동일 ID와 기준 revision, 더 높은 서버 revision, 허용된 PATCH 필드 및 로컬 의도 값까지 검사한다. SONG 대표 키 종류/이동량은 결합 비교한다. 삭제·휴지통·보관 상태, CREATE, RECORDING, 다른 오류·불충분 근거는 자동 재적용 후보를 만들지 않는다. 현재 작업 모델이 서버 SongEditing/TagService·MutationRequest·저장된 오류 형식과 대조했다.

기존 op_id·본문·기준·시도 횟수·상태를 변경하지 않는다. null은 다른 해결 경로가 필요하다는 뜻이며 성공/사용자 선택 완료가 아니다. 읽기 전용 후보이므로 서버 최종 검증과 계정 fence를 대신하지 않는다. 전체 P10-07 완료 아님.

## 실제 검증

- `flutter test --no-pub test/metadata_conflict_test.dart test/three_way_merge_test.dart test/change_payload_validation_test.dart`: **27 PASS**(어댑터9+순수비교12+기존도메인6).
- `dart analyze lib/core/sync/metadata_conflict.dart test/metadata_conflict_test.dart`: **No issues found**.
- 충돌 메모, 장치 시각 무관, 대표 키 결합, 동일 태그 이름, 삭제/보관 거절, 잘못된 기준/서버/로컬 입력, 큐 불변성 확인. 실제 사용자 데이터/폰 변경 없음.
- 로그 .local/workflow/p10-07b-test.log. 현재 모델의 코드 검토이며 독립 에이전트 검수 아님. 모델/속도 변경을 주장하지 않는다.
- 커밋은 이 파일의 Git 이력으로 식별하고 정확 SHA CI는 후속 통합 기록에 남긴다.

다음은 초기 사본의 기존 업무 사본 갱신 누락을 대조하고, 충돌 후보를 새 op_id로 보존 처리할 트랜잭션/화면 연결을 진행한다. 필수 전체 선행 완료를 임의로 선언하지 않는다.
