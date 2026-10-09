# P15-03 검색 결과와 출처 검증 토큰 (원수)

- 앞 P15-02 a9271d1cf5dbc2824385328b9b7a1d43c0575a71 필수 서버·MySQL CI PASS/완료 폰 알림 서버 접수 후 finish02/begin03. 승인 P15-01~08, 현재 gpt-6.1-sol/medium 고정.
- 원본 계획 p753~755·설계13.1 p1047~1050·R085/R089. GET /v1/karaoke/search(brand TJ/KY, kind TITLE/ARTIST/NUMBER 기본TITLE, q), 기존 bearer·기기 인증 사용. 성공/ApiException 오류 Cache-Control:no-store. 중복/미지 조건·잘못된 브랜드 거부, 다른 메서드 deny.
- 응답 results에 brand/number/title/artist/provider/source_ref/source_token/expires_at/matched_song_id 제공. 앞 어댑터·계정 제한과 연결. 현재 인증 계정 ACTIVE/TJ/정확한 문자열 번호만 한 SQL 조회로 연결하며 금영은 null. 제목/가수·괄호로 병합하거나 버전 추론하지 않음. 조회 뒤 세션 재검증. 결과/개인 연결 캐시 없음.
- SourceTokens는 독립32byte 서버 키 + AES-GCM, 별도 AAD/랜덤IV/canonical Base64/크기 제한/미래 발급 거부, provider/brand/number/원본/출처/발급·만료 고정24h 인증. 계정 접근 권한을 대체하지 않음. 서버 재시작 임의 키/기본 키 사용 없음. songrecord.karaoke.key-base64는 배포 환경의 비밀 설정으로 주입하며 비어 있으면 검색503 SEARCH_SIGNING_UNAVAILABLE, 외부 호출 이전 fail closed. 실제 운영 키를 테스트 키로 대신하지 않음. 키 설정과 P00 제공자 조건 확인은 배포 전 필요.
- 일괄 API test bootJar 종료0 BUILD SUCCESSFUL57초, XML632: 성공552/실패0/오류0/MySQL skip80. 현재 모델 검토에서 만료 시각의 ms 정밀도 일치 보완 후 *karaoke.* test bootJar 종료0/10개 성공. 전체 관련 회귀+새 시각 경계, 실제 HTTP 직렬화/인증·method 제한/no-store/빈 결과·금영null/H2 임시 DB의 타계정·삭제곡 제외 검증. 사용자 DB 초기화 없음.
- 현재 모델 별도 검토: 원본 필드/브랜드/번호/원본 보존·출처 암호화/시각·계정 격리·검사 결과·기존 후보 회귀 대조, 정밀도 지적 해결. 새 사용자 실기 없음. P15-04에서 실제 검증기를 기존 등록 경로에 연결하고 만료 TJ 재조회 적용 예정.
- 최종 SHA/필수 CI는 푸시 뒤 대조. 모델 관측 gpt-6.1-sol, 요청medium/로그 추론 수준 관측 없음. 개념: 출처 토큰은 검색 후보가 변조되지 않았다는 근거이며 사용자 계정 접근 권한과 별개.
