# P10-06n — 목록·목록 항목·과거 컨디션 영구 삭제 표식

2026-10-01. P10-06 증분 변경 수신의 삭제 보존 범위 확장. 서버 V6 deletion_ledger 및 V15 ck_ledger_type의 PLAYLIST/PLAYLIST_ITEM/CONDITION UUID 표식에 근거한다. USER 계정 삭제와 RECORDING_ASSET generation은 일반 UUID 표식으로 처리하지 않는다.

CONDITION을 로컬 RECORDING_CONDITION으로 명시 변환한다. 대상 UUID 기준으로 tombstone을 저장하며 기존 로컬 입력·원본 사본·큐·파일을 제거하지 않는다. 검증된 영구 삭제보다 오래된 응답은 도메인 편집 형태 검사 전에 무시해 과거 데이터가 되살아나지 않게 한다. 더 높은 revision의 모순된 응답은 거절하고 커서를 진행하지 않는다. 표식이 없는 미지원 관계/자산 응답의 실패 검사는 유지한다. D06 고정 카탈로그를 수정하거나 과거 이름 이력을 삭제하지 않는다.

- `flutter test --no-pub test/permanent_deletion_test.dart test/change_feed_store_test.dart`: 최초 및 현재 모델 검토 보완 후 각각 **28 PASS**.
- 변경4파일 `dart analyze`: **No issues found**.
- 새3종 표식의 종류·대상 UUID·미전송 입력·원본 행 보존, 오래된 UPSERT 무시, 모순 revision 거절/커서 유지 검증.
- 로그 .local/workflow/p10-06n-test.log / p10-06n-final.log. 별도 에이전트 검수가 아닌 현재 모델 코드 검토. 모델/속도 변경을 주장하지 않는다.
- 전체 P10-06 완료 아님. 이 파일의 Git 이력으로 대상 커밋 식별, 정확 SHA 필수 CI는 후속 통합에서 확인한다. 기존 폰 검증 범위를 확대하지 않는다.
