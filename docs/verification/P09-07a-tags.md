# P09-07a 태그 관리 API

기준: P09-06 `c67f1d7589f5d4cbe9da8e1a8245d6c6f46d55aa`.
P09-07 중 기존 계정별 tag 구조의 생성·조회·이름 수정·archive를 구현한다.
컨디션은 현재 공용 고정 코드 구조이므로 개인별 정의로의 전환과 기존 데이터 보존은 P09-07b에서 처리한다.

## API

| 경로 | 입력 | 결과 |
| --- | --- | --- |
| GET /v1/tags | state=ACTIVE(기본)/ARCHIVED/ALL, limit=1~100(기본 50), cursor | items/count/next_cursor |
| POST /v1/tags | id, name | 새 태그 201, 기존 활성 UUID 200 |
| PATCH /v1/tags/{id} | base_revision, name | 수정된 Tag |
| POST /v1/tags/{id}/archive | base_revision | 보관된 Tag |

인증 계정으로 범위를 제한하고 X-Device-Id를 검증한다. 쓰기는 Idempotency-Key를 사용한다.
Tag 응답은 id/name/revision/archived_at/updated_at이며 user_id를 받거나 반환하지 않는다.
Cache-Control: no-store를 설정한다. 다른 계정/없는 수정 대상은 404다.

## 이름과 중복

앞뒤 계약 공백을 제거한 표시명을 Unicode code point 1~50자로 검증한다.
중복 키는 기존 V4 계약대로 UTF-8(NFC(계약 공백 제거), ASCII A-Z→a-z)이다.
예를 들어 ` HELLO `와 `hello`, 조합형과 완성형 같은 문자는 활성 이름 중복이다.
ASCII 이외의 대소문자는 추가 변환하지 않는다. DB 표시용 collation을 중복 판단에 사용하지 않는다.

같은 계정의 활성 이름 중복은 409 TAG_NAME_IN_USE다. 다른 계정에는 같은 이름을 허용한다.
보관한 이름은 새 UUID로 다시 만들 수 있다. 기존 보관 UUID 재생성/이름 수정은 TAG_ARCHIVED다.
같은 활성 UUID를 다른 op_id로 재전송해도 기존 이름을 덮어쓰지 않는다. 영구 삭제 원장 UUID는
CreationGuard가 RESOURCE_PURGED로 막는다. 다른 계정과 UUID 충돌 시 TAG_ID_CONFLICT만 반환한다.

## 보관과 과거 녹음

이름을 바꾸거나 보관해도 recording_tag 관계와 name_snapshot, recording revision은 유지한다.
보관은 물리 삭제가 아니다. 기본 목록에서는 숨기고 state=ARCHIVED/ALL로 확인할 수 있다.
이미 보관된 태그의 archive 재요청은 최초 archived_at을 유지한다.
동일 op_id는 기존 응답을 재사용한다. 새 op_id의 유효한 archive 요청은 revision/변경 로그를 증가시킨다.

P09-04 녹음 수정 경로와 같은 USER_SYNC 잠금을 공유하므로 신규 선택과 보관이 계정 단위로 직렬화된다.
기존에 붙어 있던 보관 태그는 유지할 수 있고 당시 이름도 보존한다. 해제한 보관 태그를 새로 선택하면
TAG_ARCHIVED로 거절한다. 새 태그 연결에만 현재 이름을 스냅샷으로 저장한다.

## 일관성과 목록

정의 변경·정규화 키·revision·TAG UPSERT 변경 로그·change_seq·멱등 응답을 한 트랜잭션으로 확정한다.
실패하면 함께 롤백한다. archive를 DELETE 동기화로 보내지 않는다.

목록은 정규화 키 바이트, UUID 오름차순의 keyset 조회다. 곡의 자연 정렬과는 별도 목록 계약이다.
state 필터를 count/items 모두에 적용하고 같은 읽기 시점에서 조회한다. 커서는 계정·state·limit과
계정 변경 세대에 묶인다. 태그 변경 후 오래된 커서는 LIST_CURSOR_EXPIRED로 재조회를 요구한다.
임의/중복 파라미터와 범위를 벗어난 limit는 거절한다.

## 검증

- HTTP: 이름 정규화/50자 경계, 이름 수정 충돌, 인증·계정 격리, 삭제 원장,
  archive 입력·최초 시각 유지, 보관 목록, 페이지/커서 조건 불일치/변경 후 만료.
- H2/전체 Flyway MySQL 공통: 생성 재전송·활성 이름 중복, 기록 연결 후 이름 수정·archive,
  당시 이름/녹음 불변, 보관 후 동일 이름 새 UUID 생성, 보관 연결 유지·해제 후 재선택 차단,
  변경 로그 실패 롤백·재시도, 동일 이름 동시 생성의 단일 승자, 여러 페이지 및 이모지 스냅샷.
- H2 VARCHAR는 UTF-16 길이를 세므로 태그 테스트용 컬럼만 100 단위로 확장한다.
  실제 MySQL utf8mb4의 50 code point 제약은 그대로 유지하며 공유 테스트에서 검사한다.
- API 계약에 네 경로와 Tag/TagCreate/TagPatch/TagArchive/TagPage 및 경계 사례를 추가한다.

새 마이그레이션/모바일 화면 변경은 없다. MySQL 전용 실행 결과는 GitHub Actions에서 확인한다.
