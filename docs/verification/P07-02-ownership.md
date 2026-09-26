# P07-02 — 계정별 소유권 공통 검사

## 범위

- AccountAccess는 Bearer 세션과 X-Device-Id를 검증해 서버가 결정한 userId/deviceId/sessionId를 보관한다. 요청 본문의 user_id는 권한 근거로 사용하지 않는다.
- 기존 GET /v1/auth/me에 공통 인증 파서를 적용했다. 응답 계약은 유지한다.
- OwnershipGuard는 곡, 녹음, 재생목록, 태그, 기기, 녹음 자산, 업로드를 user_id와 식별자로 조회한다.
- 기존 곡-녹음, 재생목록-항목, 녹음-태그 관계는 소유권과 실제 관계를 함께 검사한다. 자산/업로드도 부모 녹음 소유자를 확인한다.
- 다른 계정 자료, 없는 자료, 잘못된 자료 UUID는 동일한 RESOURCE_NOT_FOUND / 404 / 빈 details로 끝난다. 메시지에 식별자, 제목, 메모, 파일 경로나 URL을 넣지 않는다.
- 매 검사에서 세션을 재확인하므로 로그아웃, 만료, 기기 폐기, 계정 삭제 시작 뒤 기존 Account 객체를 재사용할 수 없다.

## 후속 API 구현 규칙

1. AccountAccess.authenticate(authorization, deviceHeader)로 권한을 만든다. Account를 저장하거나 응답에 직렬화하지 않는다.
2. 단일 자료는 guard.require(account, Resource.SONG, id)처럼 검사한다.
3. 기존 관계 경로는 requireRecordingForSong / requirePlaylistItem / requireRecordingTag를 사용한다.
4. 새 관계 생성은 각 대상에 require를 적용한다. 아직 없는 관계를 기존 관계 검사로 확인하지 않는다.
5. 이후 실제 조회/수정 SQL에도 반드시 인증된 user_id 조건을 넣는다. 검사 결과는 미래 요청이나 변경 작업에 대한 영구 허가가 아니다.
6. 변경 작업은 도메인 트랜잭션 안에서 상태/리비전/필요한 잠금을 함께 검증한다. 이 단계의 공통 검사는 동시성 잠금 구현이 아니다.
7. 소유권과 lifecycle eligibility는 별도다. 본인 TRASHED 자료도 복구 등에 필요하므로 소유권 검사 자체는 허용한다.

업무 CRUD API와 URL 발급은 아직 구현하지 않았다. 공통 검사 추가만으로 미구현 API가 자동 보호된다고 가정하지 않는다. 검증용 HTTP 경로는 테스트 소스에만 있고 운영 SecurityConfig 허용 경로는 넓히지 않는다. SQL 마이그레이션과 모바일 변경은 없다.

## 검증

- 실제 H2 세션/계정 데이터로 A/B 계정 격리, 7종 자료, 기존 관계와 부모 불일치, 혼합 소유자 관계, 관계 부재, 후보 곡 항목을 검사한다.
- 로그아웃/만료/기기 폐기/계정 삭제 이후 재사용과 잘못된 기기 헤더는 401이다.
- 테스트 전용 HTTP 컨트롤러에서 타인/없는/잘못된 ID의 404 응답 본문이 동일하며 개인정보를 포함하지 않는지 검사한다.
- 서버 전체 test 및 bootJar, 기존 OpenAPI 검증을 실행한다. Windows 적용 스크립트는 gradlew.bat test bootJar를 재실행한다.
- 기기 수동 조작이나 앱 재설치는 필요 없다. 적용 후 CI와 API contract가 모두 성공해야 다음 단계로 진행한다.
