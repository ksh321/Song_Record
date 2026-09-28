# P09-07b 계정별 컨디션 관리

기준: P09-07a `da61f70ade93177bc70bac8b200d6b23f4447a92`.
계정별 컨디션 생성·목록·이름 수정·보관과 녹음 선택을 구현한다. 모바일 관리 화면은 후속 범위다.

## API와 식별자

| 경로 | 입력 | 결과 |
| --- | --- | --- |
| GET /v1/conditions | state=ACTIVE(기본)/ARCHIVED/ALL, limit=1~100(기본 50), cursor | items/count/next_cursor |
| POST /v1/conditions | id(UUID), name | 생성 201, 기존 활성 UUID 200 |
| PATCH /v1/conditions/{id} | base_revision, name | 수정된 Condition |
| POST /v1/conditions/{id}/archive | base_revision | 보관된 Condition |

응답은 id/code/name/revision/archived_at/updated_at이다. 인증·X-Device-Id 검증과 쓰기 Idempotency-Key를 요구한다.
소유 계정은 토큰에서 결정하며 다른 계정의 수정 대상은 404다. 응답에는 Cache-Control: no-store를 설정한다.
이름 수정·보관 URL에는 id를 사용한다. 녹음의 condition_code 및 목록 필터에는 반드시 응답의 code를 사용한다.
기본 정의의 code는 VERY_GOOD/GOOD/NORMAL/BAD이며, 사용자 정의의 code는 id와 같은 UUID다.
기본 정의는 id와 code가 다르므로 모든 컨디션에서 id를 선택 값으로 사용하면 안 된다.
녹음에는 최대 한 개를 선택하며 null로 해제한다. 목록 필터 ALL(미지정)과 NONE도 유지한다.
녹음 목록의 condition_name_snapshot은 현재 정의 이름이 아닌 당시 이름이다.

## 이름·보관·기록 보존

표시명은 계약 공백 제거 후 1~50 Unicode code point다. 중복 키는 기존 DomainOrdering의
NFC/계약 공백/ASCII 소문자 규칙과 UTF-8 바이트를 사용한다. 활성 이름 중복은 CONDITION_NAME_IN_USE다.
보관한 이름은 새 UUID로 다시 사용할 수 있지만 보관한 UUID 재생성·이름 수정은 CONDITION_ARCHIVED다.
기존 활성 UUID의 재요청은 이름을 덮어쓰지 않는다. 삭제 원장 UUID는 CreationGuard가 막는다.

이름 수정·보관은 과거 녹음의 코드·이름 스냅샷·revision을 변경하지 않는다.
이미 선택한 보관 컨디션은 유지할 수 있다. 해제한 뒤 새로 선택하면 CONDITION_ARCHIVED로 거절한다.
새 선택에만 현재 이름을 복사하며 같은 코드를 다시 보낸 요청은 과거 이름을 보존한다.

## 트랜잭션과 목록

컨디션 변경·revision·CONDITION UPSERT·change_seq·멱등 응답을 한 트랜잭션에 기록한다.
녹음 선택과 컨디션 보관 모두 USER_SYNC 잠금을 사용해 계정 단위로 직렬화한다.
실패하면 정의와 변경 로그, 응답 영수증을 함께 롤백한다. archive는 DELETE 동기화가 아니다.
동일 op_id는 최초 응답을 재사용한다. 새 op_id와 최신 revision으로 반복 보관하면 최초 archived_at을
유지하고 revision과 변경 로그는 증가한다.
목록은 정규화 키 바이트와 UUID 순서로 조회하며 커서는 계정·state·limit·변경 세대에 묶인다.

## V15 마이그레이션

기존 불변 condition_catalog는 기본값의 원본으로 유지한다. 이전 V4는 수정하지 않는다.
condition_definition에 기존 계정별 기본 정의 네 개를 복사하고 이후 계정 생성은 AFTER INSERT
트리거에서 네 개를 함께 생성한다. 기본 정의 id는 계정 UUID와 기본 코드를 포함한 결정적 MD5 값이다.
이는 식별자 생성 용도이며 인증 토큰이나 보안 해시가 아니다.
기존 recording의 condition_code를 36자로 확장하고 (user_id,condition_code) 복합 FK로 소유권을 강제한다.
이전 녹음 행의 코드·이름·revision·updated_at 값은 유지한다. DB 트리거도 새 선택의 활성 상태와
소유권을 확인하고 같은 코드의 스냅샷 덮어쓰기를 막는다.
기본값 설치는 초기 목록 조회 대상이며 개별 change_log를 생성하지 않는다. 사용자 CRUD는 변경 로그를 남긴다.
전체 동기화 초기 스냅샷은 후속 P10 범위다.

## 검증과 실행 범위

- HTTP/H2: 이름 경계·정규화 중복, revision 충돌, 계정별 기본값, 타 계정 선택 404, 인증 401,
  사용자 코드 필터, 목록 커서 만료, 과거 이름 보존, 보관 선택 규칙.
- H2/MySQL 공유 시나리오: 생성 재전송, 이름 수정·보관, 선택 해제·재선택, 50개 이모지,
  변경 로그 실패 롤백·동일 키 재시도, 같은 이름 동시 생성의 단일 승자.
- MySQL: V9 데이터에 GOOD 선택 후 V15 이전 전후 녹음 전체 필드 비교, 신규 계정 기본값,
  스냅샷 직접 덮어쓰기 방어, Flyway 재실행 0건.
- H2의 UTF-16 문자 길이 차이는 테스트 스키마 100자로 보정하며 실제 MySQL 제한은 50 code point다.
- API 계약: wire 예제 7개, 스키마 경계 사례 122개.
- MySQL 전용 테스트는 로컬 환경에서 실행하지 않았으므로 Actions의 Idempotency MySQL과 CI를 확인한다.

적용 후 새 코드로 서버를 시작/재시작하면 Flyway가 V15를 자동 적용한다. 수동 SQL이나 휴대폰 재설치는 필요 없다.
