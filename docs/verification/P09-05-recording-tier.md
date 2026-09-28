# P09-05 녹음 티어 변경

기준 커밋: 84f244822ba1fb4a1007d3b602f99952d531c674 (P09-04).
근거: 구현계획서 P09-05, 설계서 녹음 티어·자동 보관 역할·동기화 규칙.

## API

`PATCH /v1/recordings/{id}/tier`

```json
{"base_revision": 2, "tier": "A"}
```

Authorization, X-Device-Id, Idempotency-Key를 사용한다. tier는 S/A/B/C/D/null 중 하나이며
필드를 생략할 수 없다. null은 평가 해제다. 불필요한 필드·중복 JSON 키·잘못된 revision은 거절한다.

인증 계정의 ACTIVE·SAVED 녹음만 허용한다. DRAFT는 RECORDING_NOT_SAVED,
비활성은 RECORDING_NOT_ACTIVE, 오래된 revision은 REVISION_CONFLICT(409)다.
다른 계정 또는 없는 녹음은 404다. 충돌의 current는 잠금 안에서 읽은 현재 녹음 메타정보/태그다.

응답은 P09-04의 RecordingEdited 메타정보 스냅샷을 공유하고 Cache-Control: no-store를 설정한다.
일반 녹음 PATCH에서는 계속 tier를 거절하여 전용 API의 검증/작업 등록을 우회하지 못한다.

## 트랜잭션과 영향 범위

- 기존 receipt → USER_SYNC → recording → job 잠금 순서를 사용한다.
- 녹음 tier, revision, 정책 작업, change_log/change_seq, 멱등 응답이 함께 확정/롤백한다.
- 같은 op_id 재전송은 저장된 응답만 돌려주며 revision/작업/변경 로그가 증가하지 않는다.
- 같은 revision의 서로 다른 동시 수정은 하나만 성공하고 다른 요청은 409다.
- 새로운 op_id로 현재와 같은 티어를 보내면 revision/변경 로그는 증가하지만 재계산 작업은 추가하지 않는다.
- song_id가 있는 녹음의 실제 티어 변경(평가 해제 포함)은 POLICY_RECALCULATE 작업을 추가한다.
  aggregate_id는 song_id, payload는 song_id/recording_id/recording_revision/reason이다.
- 미연결 녹음도 평가할 수 있지만 재계산할 곡이 없으므로 작업은 추가하지 않는다.
  후속 재연결 단계에서 연결 대상 곡의 재계산을 등록한다.
- 곡의 song_tier/revision, 녹음의 다른 입력·시각·연결·파일 명세는 바꾸지 않는다.
- 파일 존재 여부나 용량 검사에 의존하지 않는다. 목록 필터/정렬은 새 티어를 읽고 기존 커서는 만료된다.
- 실제 정책 작업 소비와 선정 계산은 P11 범위다. 이번 단계에서 서버 파일을 업로드/삭제하지 않는다.

## 검증

HTTP에서 모든 허용 티어/해제, 초안·비활성 차단, 인증·계정 격리, 잘못된 입력,
충돌 응답, 목록 티어 필터/커서 무효화를 확인한다.

H2와 전체 Flyway MySQL이 같은 시나리오를 실행한다:
서버 파일 없는 SAVED 평가, 곡 티어·파일·다른 메타정보 불변, 동일 키 재전송,
같은 값의 새 요청, 해제 시 재계산, 동일 revision 동시 요청의 단일 승자,
change_log 강제 실패 시 tier/revision/job/receipt/change_seq 전체 롤백과 같은 키 재시도.

API 계약에 구현 상태/응답 및 TierPatch 경계 사례를 추가한다.
새 마이그레이션과 앱 UI 변경은 없다. MySQL 검증은 Actions 결과로 확인한다.
