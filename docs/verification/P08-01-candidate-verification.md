# P08-01 TJ 후보 검증 경계

## 범위와 신뢰 경계

CandidateVerifier는 source_token을 검증한 뒤 provider, brand, number, 원본 title/artist, issuedAt/expiresAt을 반환하는 서버 인터페이스다. TjCandidates는 검증 결과의 유효기간과 TJ 브랜드를 확인한다. 등록 서비스는 여기서 반환된 번호/원본을 사용해야 하며 클라이언트 brand/number/원본을 덮어씌우면 안 된다.

이번 단계는 실제 외부 검색, source_token 서명 발급, 만료 후 같은 번호 재조회, 곡 생성 HTTP API를 구현하지 않는다. 실제 검색 어댑터/위조 방지 토큰 발급과 재검증은 P15-03/04, 곡 생성은 P08-02에서 연결한다. 지금 기본 검증기는 503 CANDIDATE_VERIFICATION_UNAVAILABLE로 닫혀 있어 임의 번호를 신뢰하지 않는다.

## 개발용 후보

개발 통합용 고정 allowlist이며 실제 TJ 데이터가 아니다. dev와 candidate-fixtures 두 프로필을 모두 명시할 때만 켜진다. candidate-fixtures만 켜거나 prod/production과 함께 켜면 서버 구성이 실패한다. dev만으로는 활성화되지 않는다. 배포 환경은 이 두 개발 프로필을 사용하지 않아야 한다. 프로필 이름 검사는 배포 권한이나 환경 자체를 자동 판별하는 보안 장벽은 아니다.

| source_token | 브랜드 | 번호 | 용도 |
|---|---|---|---|
| dev-source-tj-001 | TJ | 990001 | 정상 등록 후보 |
| dev-source-tj-002 | TJ | 990002 | 같은 제목/가수지만 다른 번호 |
| dev-source-ky-001 | KY | 990001 | 검증된 금영 후보도 등록 거절 |

이 번호의 실제 TJ/KY 수록 여부를 주장하지 않는다. 원본은 ‘개발 검증 곡’/‘개발 검증 가수’, provider는 DEVELOPMENT_FIXTURE다. 고정 문자열은 서명 토큰이 아니며 운영 증명으로 사용할 수 없다. 서버가 가진 정확한 allowlist 항목만 허용하고 brand/number JSON, 숫자 단독, 변경한 문자열, 뒤 공백을 거절한다. 개발 후보의 발급 시각은 해당 bean 생성 시각으로 고정하며 매 검증마다 만료를 연장하지 않는다. 개발 서버 재시작 시 새 후보로 취급되는 편의 구현이며 실제 발급 정책과 구분한다.

## 공통 검사

- source_token은 필수이며 8192자를 넘으면 거절한다.
- provider/번호/원본은 검증 어댑터의 반환값이다. 번호는 ASCII 숫자 1~20자리, 제목/가수는 공백만으로 구성되지 않은 200 코드 포인트 이하 값이다.
- 발급 시각이 미래이거나 유효기간이 0 이하 또는 24시간 초과면 SOURCE_TOKEN_INVALID(400).
- expiresAt과 현재 시각이 같아진 순간부터 SOURCE_TOKEN_EXPIRED(409).
- 유효한 KY 후보도 곡에는 SONG_TJ_REQUIRED(400), 목록에는 기존 계약 PLAYLIST_TJ_REQUIRED(400).
- SOURCE_TOKEN_EXPIRED는 P15 재조회 어댑터 연결 전의 명시적인 만료 결과다. 외부 장애를 TJ_NOT_FOUND로 바꾸거나 수동 등록 성공으로 처리하지 않는다.
- 오류 details에는 증명/원본을 넣지 않고 Verified.toString도 내용을 숨긴다.

후보 증명은 공개 검색 출처 증명이며 사용자 세션 인증/자료 소유권 검증을 대체하지 않는다. 실제 생성 단계는 AccountAccess, 멱등 처리, UUID 생성 검사와 함께 사용한다. 이번 서비스는 DB를 변경하지 않는다.

## 테스트

CandidateTests 10개: 정확한 증명과 서버 원본, 동일 제목의 다른 번호 구별, 숫자/brand 조작/빈값/과대 입력, 유효 KY의 곡·목록 거절, 24시간 직전/정각 만료, 미래/초과 유효기간, 기본 거절, 명시적 개발 허용, 위험한 프로필 조합의 기동 실패, dev 단독 거절.

실제 외부 공급자의 서명 검증/네트워크 장애/검색 데이터 이용 조건을 검증한 것은 아니다. 이번에는 새 MySQL 테스트가 필요하지 않으며 기존 MySQL 회귀 검증을 유지한다. 적용 후 CI / API contract / Idempotency MySQL을 확인한다. 휴대폰 테스트·환경변수/프로필 변경·DB 마이그레이션은 이번 적용에 필요 없다.
