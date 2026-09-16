# D06 — 컨디션 0~1개와 사용자 태그
- 상태: 확정 / P00-06 / 2026-09-16
- 승인: 사용자 컨디션 예시·0~1개 선택·태그 복수/커스텀 지정
- 관련: R029·R030, X05, P04·P09·P18·P23
- 사례: [P00-06](../contracts/P00-06-examples.md)

## 컨디션
초기 선택지는 다음 네 단계로 고정한다. 임의로 '매우 안 좋음' 등의 단계를 추가하지 않는다.

| 코드 | 표시 | 순서 |
|---|---|---:|
| VERY_GOOD | 매우 좋음 | 1 |
| GOOD | 좋음 | 2 |
| NORMAL | 보통 | 3 |
| BAD | 안 좋음 | 4 |

기본은 미선택(null)이며 자동으로 보통을 선택하지 않는다. 녹음당 0~1개, 다른 항목 선택 시 교체하고 선택 해제도 가능하다. 컨디션의 사용자 생성·이름 변경·archive UI는 초기 출시에서 제공하지 않는다. 사용자가 만드는 분류는 태그다.
이는 원 설계의 사용자 컨디션 생성/수정/archive 기능을 고정 단계로 변경하는 사용자 선택의 구체화다. 관련 원본 DOCX/HTML은 보존하고 충돌 시 본 계약을 우선한다.

## 태그
계정별 사용자 커스텀 이름으로 생성·수정·archive 가능하다. 녹음 하나에 서로 다른 태그 여러 개를 붙일 수 있다. 신규 제품상 개수 제한은 추가하지 않으며 API 공통 요청 크기 한도는 별도 적용한다.
태그 필터는 기존대로 한 항목만 선택하고 다른 필터와 AND로 결합한다. 선택된 태그 해제는 그 녹음 관계만 제거하며 태그 전체 archive와 다르다.
이름은 D05 trim 후 1~50자다. 동일 계정의 활성 태그에서 NFC+ASCII 소문자 비교키가 같은 이름은 중복 생성 대신 기존 태그를 안내한다. 표시값을 그 키로 덮어쓰지 않는다.
archive는 신규 선택에서 숨기고 과거 관계와 이름 스냅샷을 보존한다. 이름 변경도 과거 녹음에 저장된 당시 이름을 일괄 변경하지 않는다.

## API·DB 계약
기본 /v1, 인증·device_id·Idempotency-Key·base_revision 공통 규칙을 따른다.
- GET /conditions: 위 고정 카탈로그(code, name, order, catalog_version) 반환. 변경 API POST/PATCH/archive는 신규 구현하지 않으며 호출 시 405 CONDITION_CATALOG_READ_ONLY.
- POST /recordings와 PATCH /recordings/{id}: condition_code는 위 enum 또는 null, tag_ids는 해당 계정의 태그 UUID 배열. PATCH 누락=유지, condition_code:null=해제, tag_ids:[]=모두 해제. tag_ids:null은 400.
- 배열에 중복 태그 ID가 있으면 400 DUPLICATE_TAG_ID. 타인 태그는 404, 새로 연결하려는 archived 태그는 409 TAG_ARCHIVED.
- 이미 연결된 archived 태그는 다른 필드 수정 시 그대로 유지 가능하다. 명시적 tag_ids 전체 교체에도 기존 관계는 유지 가능하며 신규 연결만 거절한다.
- 일반 PATCH의 condition_ids 등 복수 입력은 400으로 거절한다. 동기화·백업 가져오기도 동일 검증.
- Recording에는 nullable condition_code와 당시 condition_name_snapshot을 둔다. 서버가 카탈로그에서 스냅샷을 만든다. RecordingTag는 (recording_id, tag_id) 유일성과 계정 소유권을 강제하고 이름 스냅샷을 보관한다.
- /tags GET·POST·PATCH 및 POST /tags/{id}/archive는 기존 경로를 유지한다. 생성 201, 즉시 변경 200, 충돌 409.

## 과거 자료
기존 커스텀 컨디션/복수 관계가 포함된 과거 형식은 이름·관계를 보존한 채 이관 보류 데이터로 유지한다. 네 단계로 임의 추정·삭제하지 않는다. 편집 시 사용자가 새 단계 하나/미선택을 정하도록 안내하며 과거 스냅샷 이력은 유지한다. 현재 프로젝트에는 배포된 앱 데이터가 확인되지 않았으며 실제 이관 검증은 P04/P22에서 수행한다.
