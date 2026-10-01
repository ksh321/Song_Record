# P10-07c — 녹음의 결합 필드·태그 충돌 비교

2026-10-01. P10-07 원본 3방향 비교의 녹음 메타데이터 어댑터. 기존 P10-07a/b 순수 비교 구조를 확장하며 아직 큐/HTTP/UI에 쓰기 동작을 연결하지 않는다.

- RecordingEditing/RecordingRating/RecordingLinking과 MutationRequest 계약을 대조했다. 활성·동일 저장 상태의 메타데이터 수정만 비교하며 곡 연결 이동/파일 저장 상태 전환/초안 평가는 별도 해결 경로로 남긴다.
- 키 종류·이동량과 recorded_at·timezone_id·offset을 각각 결합 비교한다. 태그는 검증된 UUID 집합을 정렬 복사해 비교하며 배열 순서만 다른 결과를 충돌로 만들지 않는다. 저장된 이름 이력을 바꾸거나 새로운 이름을 만들어 넣지 않는다.
- 로컬 선택 태그의 중복/비정상 UUID, 저장 완료 녹음의 필수 값 삭제, 원본 기기 변경은 거절한다. 기기 시각을 승자 판단에 사용하지 않는다. 원래 큐와 요청·서버 스냅샷은 그대로 유지된다.
- 입력 정규화·시간대 카탈로그·태그 소유권/보관 여부 등 최종 서버 검증은 이 읽기 전용 비교가 대신하지 않는다. 지원하지 않는 경우 자동 재전송하지 않는다.

실제 검증:
- `flutter test --no-pub test/metadata_conflict_test.dart test/three_way_merge_test.dart test/change_payload_validation_test.dart`: **33 PASS**.
- 현재 모델 검토에서 SAVED 필수 값을 로컬 의도뿐 아니라 기준/서버에도 검사하도록 보완했다. 이후 `flutter test --no-pub test/metadata_conflict_test.dart`: **15 PASS**.
- 대상2파일 `dart analyze`: 명시 List 타입 보완 후 **No issues found**.
- 로그 .local/workflow/p10-07c-test.log, p10-07c-final.log. 현재 모델 직접 검토이며 독립 에이전트 검수 아님. 실제 모델/속도 변경을 주장하지 않는다.

전체 P10-07 완료가 아니다. 충돌 해결 선택/새 op_id 보존 트랜잭션/실제 화면 연결 및 해당 SHA CI는 후속 단계다. 기존 USER-025 실기를 확대하지 않는다.
