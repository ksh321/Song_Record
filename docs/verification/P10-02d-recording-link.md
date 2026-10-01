# P10-02d — 의존 순서 전송: 녹음 곡 연결 전용 경로

2026-10-01. 구현계획서 P10-02 ‘의존 순서 전송’ p00579~580의 미지원 경로를 보완하는 세부 실행 식별자다. c의 티어 구현과 분리하며 기존 RecordingController/RecordingLinking의 승인된 계약을 연결한다.

## 구현과 검토

- `mutation_request.dart`: 녹음 PATCH의 base_revision/song_id 두 필드만 전용 /v1/recordings/{id}/song으로 보낸다. 연결 해제는 명시적 null, 연결은 정규 UUID다. 다른 변경을 섞거나 아직 서버 기준이 없는 요청은 기존 큐에 보존한다. op_id·payload는 재작성하지 않는다.
- 기존 DependencyPlanner가 대상 곡의 승인된 기준과 삭제 여부를 확인한다. 선행이 없거나 삭제된 곡은 attempt0 그대로 대기하며 무관한 대상까지 차단하지 않는다.
- `metadata_response.dart`: 성공 응답의 연결 대상, 실제 이동 여부에 따른 link_revision 증가, 알려진 기존 녹음 당시 필드/메모/티어/컨디션 보존을 확인한다. 잘못된 응답은 ACK하지 않는다. 충돌 응답은 기존 충돌 보존 처리로 전달한다.
- 현재 모델 별도 검토: 원본 P10-02, Java RecordingLinking의 정확한 두 필드 계약·같은 대상 재지정·revision/link_revision 동작, 기존 claim/ACK 및 planner를 실제 diff와 대조했다. 별도 작업자/검수자 위임 없음. 인증·관계 보존 위험 때문에 높은 추론 수준이 적합하나 현재 실행 모델/속도 설정 변경을 확인했다고 주장하지 않는다.

## 실제 검증

```text
flutter test --no-pub test/recording_link_dispatch_test.dart test/recording_tier_dispatch_test.dart test/metadata_dispatcher_test.dart --reporter expanded
flutter analyze --no-pub lib/core/sync/mutation_request.dart lib/core/sync/metadata_response.dart test/recording_link_dispatch_test.dart
git diff --check
```

**31개 통과, 분석 No issues found.** 새 연결/해제/동일 대상/미존재/삭제 대상 및 변조 응답 검증6개와 기존25개. 실제 임시 SQLite와 합성 파일4바이트를 사용해 녹음 UUID·제목 스냅샷·메모·파일 바이트 보존, 정상 ACK revision2, 막힌 요청 attempt0, 증분 커서 미전진을 확인했다. 응답 target/link_revision/title/tier 변조는 거절한다. 분석 중괄호 권고2건 보완. 제품/원본 데이터 삭제나 사용자 폰 실기 없음.

로그: .local/workflow/p10-02d-link-test.log. 커밋/정확 SHA CI 후속 기록. 사용자 직접 할 일0건. 전체 P10-02 완료는 아니며 미구현 목록/관계/파일 API와의 연결은 선행 구현에 맞춰 진행한다. P10-05의 조회 투영·앱 흐름 연결도 남아 있다.
