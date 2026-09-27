# P08-02 TJ 곡 생성 API

## 구현 범위

POST /v1/songs를 연결한다. Authorization Bearer, X-Device-Id, Idempotency-Key(UUID), JSON 본문이 필요하다. AccountAccess가 현재 세션과 기기를 검증해 소유 계정을 정한다. user_id/brand/tj_number/source 원본 필드를 클라이언트가 직접 넣으면 거절한다.

현재 source_type=TJ만 구현한다. MANUAL은 P08-04, 곡 조회/편집/앱 Repository 연결은 해당 후속 단계다. 기본 후보 검증기는 P08-01대로 503을 반환한다. 실제 공급자 검색은 P15이고 개발용 통합은 dev,candidate-fixtures 프로필의 가상 후보만 사용한다. 이번 적용에는 프로필을 바꾸거나 휴대폰을 재설치할 필요가 없다.

## 요청과 응답

필수: id, source_type=TJ, source_token.
선택: title, artist, version_code, note, tier.
- title/artist 생략 시 검증된 원본을 표시값으로 사용한다. 개인 표시값은 공통 공백 trim/코드 포인트 길이 검증을 적용한다.
- version_code 생략 시 NORMAL. NORMAL/MR/LIVE만 허용.
- note 생략/null은 빈 문자열. 줄바꿈을 정규화하고 2000 코드 포인트까지 허용.
- tier 생략/null은 미정, 나머지는 S/A/B/C/D.
- title/artist/version_code의 명시적 null과 알 수 없는 필드는 400 VALIDATION_FAILED.
- MANUAL/대표 키 등의 후속 생성 입력은 이번 요청에 포함하지 않는다.

최초 생성은 201, created=true, canonical_song_id와 Song을 반환한다. Song revision=1, lifecycle_state=ACTIVE이며 updated_at은 UTC 밀리초 정밀도로 기록한다. 응답 Cache-Control은 no-store다. Song 조회 계약대로 tier 이름을 사용하며 DB song_tier에 매핑한다.

동일 생성 UUID 또는 이미 예약된 TJ 번호의 ACTIVE 곡은 200, created=false로 기존 곡을 반환하고 기존 편집값을 덮어쓰지 않는다. 새 UUID를 기존 곡 UUID로 별도 별칭 저장하지는 않는다. 상세 동시성/ID 매핑 검증은 P08-03에서 확장한다. TRASHED는 SONG_RESTORE_REQUIRED, PURGE_PENDING은 SONG_PURGE_PENDING, 삭제 표식/기존 PURGED UUID는 RESOURCE_PURGED, UUID의 기존 다른 번호/종류는 SONG_ID_CONFLICT다. 요청 UUID의 삭제 표식 검사가 번호 재사용보다 먼저다.

## 저장과 트랜잭션

1. 인증과 구조/입력 검증.
2. IdempotentMutations가 영수증을 예약하거나 기존 응답을 재생한다.
3. 새 요청이면 source_token을 로컬 검증한다. 이미 완료된 같은 요청은 만료된 후보를 다시 검증하지 않고 영수증 응답을 반환한다.
4. CreationGuard가 계정 sync 행과 UUID를 검사한다. 해당 계정의 생성·수정·삭제는 공통 sync 잠금 규칙에 참여해야 한다.
5. 새 곡은 AccountChanges.write에서 song, song_source, change_log, user_sync_state를 함께 저장한다.
6. 최종 응답 영수증까지 같은 트랜잭션으로 커밋한다. 중간 실패 시 모두 롤백한다.

song은 개인 표시값/버전/메모/티어다. song_source.source_title/source_artist는 검증된 원본 그대로다. 기존 스키마의 provider='TJ' 제약을 유지한다. 검증 어댑터 이름과 번호는 source_ref에 provider:number 형태로 저장하며 source_token 자체는 저장하지 않는다. verified_at은 검증/저장 시각이다.

검증 인터페이스는 이 경로에서 로컬 검증만 수행해야 한다. P15에서 만료 토큰 외부 재조회가 필요하면 트랜잭션 밖에서 수행한 결과를 전달하는 경계를 별도로 추가한다. 현재 DB 잠금을 잡은 상태에서 외부 검색 HTTP를 호출하지 않는다.

## HTTP 보안 경계

별도 stateless SecurityFilterChain이 정확한 POST /v1/songs만 컨트롤러로 전달한다. permitAll은 필터 레벨에서 전달을 허용한다는 뜻이며 컨트롤러 서비스가 실제 bearer/device 인증을 수행한다. 누락 인증은 401이다. GET /v1/songs와 나머지 하위 경로는 아직 403으로 닫힌다. 쿠키 세션/폼 로그인/HTTP Basic을 도입하지 않는다. CSRF는 이 bearer 전용 체인에서 비활성화한다.

## 검증

SongCreationTests는 실제 Spring MVC/Security 체인과 H2 JDBC를 함께 사용한다. 201 기본값, 편집값과 원본 분리, 응답 재전송/본문 충돌, 인증 누락/미구현 경로 차단, 임의 필드/KY 거절, source 저장 실패 전체 롤백, 같은 번호 canonical 반환/메모 보존, 삭제 표식과 휴지통 거절을 확인한다.

H2 예약 번호 생성식은 해당 엔진의 IN-상수 집합이 닫힌 DDL 연결을 참조하는 문제를 피하도록 유효 lifecycle 범위에서 동등한 CASE 식을 쓴다. 운영 SQL은 수정하지 않는다. 실제 V2 song/song_source DDL, generated 예약 번호와 source INSERT trigger는 MySqlIdempotencyTests에서 검증한다. MySQL 검사에서는 source 제약 실패 시 곡/출처/변경 로그/영수증이 늘지 않는지도 확인한다.

MySQL 전용 테스트는 제작 환경에서 실행하지 못하므로 Actions에서 확인한다. 새 마이그레이션은 없다. 최신 CI / API contract / Idempotency MySQL 모두 성공해야 단계 검증 완료다.
