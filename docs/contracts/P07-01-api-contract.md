# P07-01 공통 API 계약

기준: 설계서 v1.11 §12, 구현계획 P07-01, P00의 D02~D11 결정서,
실제 P06 인증 코드(`c1e9826`). OpenAPI 표준: https://spec.openapis.org/oas/v3.1.1.html.

## 이번 범위

`openapi.yaml`은 공통 wire 형식과 현재 인증 API의 실행 가능한 계약이다.
9개 인증 operation은 `x-implementation-status: implemented`, 곡·녹음·작업 조회의
12개 operation은 `planned`이다. 후자는 응답/요청의 공통 형식을 적용한 후속 구현 목표이며
현재 서버에서 사용할 수 있는 API 목록으로 오해하면 안 된다.

59개 schema에 UUID, UTC/날짜, enum, 리소스 revision, 오류, 페이지, 비동기 접수,
곡·녹음 생성/PATCH를 정의한다. 전체 제품의 모든 API 세부 계약을 끝냈다는 의미는 아니다.
플레이리스트·태그·검색·차트·동기화·업로드·보관·삭제·이식용 백업·탈퇴의 세부 경로는
각 도메인 단계에서 이 공통 형식을 재사용해 추가한다. 필터/안정 정렬/커서 구현은 P07-08,
소유권/멱등성/revision/작업 실행은 P07-02 이후 범위다.

## 호환성과 명시한 차이

| 항목 | 계약 |
|---|---|
| 기본 경로 | `/v1`; 개인 API는 Bearer와 `X-Device-Id` 사용 |
| 인증 DTO | 이미 배포한 camelCase 유지: `userId`, `refreshToken`, `challengeId` 등 |
| 업무 DTO | 설계서에 맞춰 snake_case: `base_revision`, `recorded_at` 등 |
| refresh/logout | Bearer 대신 본문의 `refreshToken`과 `deviceId`로 증명 |
| auth 응답 | 기존 성공 200 및 `Cache-Control: no-store` 유지 |
| 연결 해제 | 현재 구현은 Bearer+기기 헤더, 본문 없음. 앱이 보내는 빈 객체도 허용 |
| 마지막 수단 오류 | 현재 코드 `LAST_IDENTITY_REQUIRED`; 설계서의 `LAST_IDENTITY`와 이름이 다름 |
| 해제 재인증 | 설계서 §12.2의 재인증 proof/base_revision은 현재 미구현. 계약 문서 추가로 구현된 것으로 간주하지 않음 |
| 컨디션 | D06이 §12.3의 이전 설명을 구체화함. 네 코드 고정 카탈로그이며 사용자 생성/수정/삭제 API를 만들지 않음 |

인증 요청을 임의로 snake_case로 변경하지 않는다. 해제 재인증 요구와 오류 코드 명칭을
통합할 때는 별도 인증 변경으로 앱/서버를 함께 수정하고 회귀 검증해야 한다.

## PATCH와 null

- `base_revision` 필수이며 1 이상의 정수다. 누락한 변경 필드는 유지한다.
- nullable 필드만 명시적 null로 해제한다. `tier`, `condition_code`, `note` 등은 null을 허용한다.
- `tag_ids` 누락은 유지, 빈 배열은 전부 해제, null/중복 ID는 오류다.
- `source_type`, `tj_number`, `user_id`, `id`를 곡 PATCH에 포함하지 않는다.
- DRAFT 녹음은 입력 미정을 허용한다. SAVED 전환은 기존 값과 변경값을 합쳐 필수 입력을 검증한다.
- `song_id`/녹음 tier는 전용 API에서 수정하며 과거 스냅샷을 곡 기본값으로 덮어쓰지 않는다.
- 제목·가수·태그·목록명은 계약 공백 trim 후 code point 수를 센다. 메모는 줄바꿈 통일 후 센다.
  JSON Schema 길이 검사는 이미 정규화한 wire 값을 대상으로 하며 정규화를 대신하지 않는다.

## 페이지·비동기·오류

목록 limit는 기본 50, 1~100이다. 마지막 페이지의 `next_cursor`는 null이다.
커서는 불투명하며 계정/필터/정렬/조회 세대가 바뀌면 폐기한다. UUID는 하이픈을 포함한
소문자 문자열이고 TJ 번호는 선행 0을 유지하는 문자열이다. 시각은 UTC Z, 날짜 필터는
Asia/Seoul 달력 날짜다. 정렬의 ID 동률 기준은 D02/D03을 따른다.

202의 `AsyncAccepted`에는 `operation_id`와 `/v1/operations/{id}` 형태의 `status_url`이
들어간다. 이는 접수 결과이며 업로드/검증/삭제 완료를 뜻하지 않는다. 향후 비동기 경로는
이 schema를 참조한다. 현재 문서의 인증 경로가 202를 반환한다고 바꾸지 않는다.

오류는 `error.{code,message,retryable,request_id,details}` 구조다. 소유권 실패와 미존재는
같은 404로 처리하고 토큰, 파일 URL, 타인 자료, 메모 원문을 details/로그에 넣지 않는다.
`REVISION_CONFLICT`의 current는 소유권 확인을 통과한 리소스만 담는다.

## 검증

- `ApiContractTests`: 실제 Java 인증 DTO의 필드/필수값, 직렬화, 컨트롤러 경로, enum을 계약 및 공용 fixture와 대조한다.
- `api_contract_test.dart`: 동일 fixture를 실제 앱 세션/challenge decoder로 읽고 enum을 대조한다.
- `verify_api_contract.py`: OpenAPI 3.1 문법, 로컬 참조, 인증 헤더, 예시와 경계/거절 입력을 검증한다.
- 기존 CI의 Java/Flutter 테스트가 위 테스트를 실행한다. 추가 `API contract` workflow가 독립적으로 OpenAPI와 JSON Schema를 검증한다.

개별 실행:

```text
services/api: gradlew test --tests '*ApiContractTests'
apps/mobile: flutter test test/api_contract_test.dart
repo root: python -m pip install -r infra/scripts/requirements-api-contract.txt
repo root: python infra/scripts/verify_api_contract.py
```

Python 도구는 별도 가상환경 사용을 권장한다. Windows 적용 스크립트는 기존 Java/Flutter 도구로
전체 테스트를 실행한다. Python 기반 검증은 CI에서 독립 가상환경을 만들고 고정 버전을 설치한다.
