# P10-02c — 의존 순서 전송: 녹음 티어 전용 경로 연결

2026-09-30. 계획서 P10-02 ‘의존 순서 전송’ p00579~580의 기존 미지원 송신 보완 세부 ID다. P10-05k의 필수 CI가 외부 환경으로 차단된 동안 선행 조건과 수정 파일을 분리해 실제 구현했다. 기존 P10-02b 검증은 유지한다.

- 근거: RecordingController의 PATCH /v1/recordings/{id}/tier, RecordingRating의 정확히 base_revision/tier 두 필드, 양수 revision, S/A/B/C/D/null 계약. 기존 서버와 계획의 녹음 평가 기능을 연결하며 제품 정책 변경 없음.
- MutationRequest.prepare는 녹음 PATCH의 단독 tier 변경만 전용 경로로 만든다. 일반 메모와 섞인 변경·잘못된 등급·미해결 기준은 전송하지 않고 기존 큐에 남긴다. body/op_id/재시도 식별을 재작성하지 않는다.
- 성공 응답은 요청한 tier와 동일하고 ACTIVE/SAVED인 전체 녹음 사본이어야 한다. 충돌 응답은 사용자가 요청한 값과 달라도 기존 충돌 보존 흐름을 유지한다.
- 파일이 없는 로컬 녹음에도 서버가 검증한 메타정보 평가를 허용한다. 파일·곡 평가·동기화 커서·기존 메모를 변경하지 않는다.

검증:
```text
flutter test --no-pub test/recording_tier_dispatch_test.dart test/metadata_dispatcher_test.dart --reporter expanded
flutter analyze --no-pub lib/core/sync/mutation_request.dart lib/core/sync/metadata_response.dart test/recording_tier_dispatch_test.dart
git diff --check
```
**25 통과, 분석 No issues found.** 합성 SQLite SAVED 녹음에 A 설정/null 해제 모두 실제 큐→claim→ACK→revision2를 확인했다. 메모 보존, 커서 미전진, 큐 완료, 파일 미요구를 확인했다. 전용 경로/허용 등급/일반 경로 유지와 다른 tier·DRAFT 성공 응답 거절도 검증했다. 실제 사용자 앱이나 서버 로그인 실기 아님.

현재 모델 별도 검토로 Java 경로·요청 검증·응답 사본, 기존 frozen wire·의존 planner·ACK 규칙과 diff를 대조했다. 새로운 위임 없음. 로그 .local/workflow/p10-02c-tier-test.log. 전체 P10-02 완료 아님. 목록/관계/파일 후속 경로가 남았고 다음 독립 후보는 기존 RecordingLinking의 전용 song 연결 경로다. 이 범위는 별도 세부 작업으로 선행 곡·삭제 대상·스냅샷/파일 보존을 검증해야 한다.

필수 GitHub CI는 계정 사용량/결제 계열 job 시작 차단으로 검증 대기다. 코드 검증 실패로 추정하거나 CI를 비활성화하지 않는다. USER-021 무료 사용량 확인 요청과 별도 관리한다.
