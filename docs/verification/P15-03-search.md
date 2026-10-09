# P15-03 검색 결과와 출처 검증 토큰 (원수)

- 앞 P15-02 a9271d1cf5dbc2824385328b9b7a1d43c0575a71 필수 서버·MySQL CI PASS/완료 폰 알림 서버 접수 후 finish02/begin03. 승인 P15-01~08, 현재 gpt-6.1-sol/medium 고정.
- 원본 계획 p753~755·설계13.1 p1047~1050·R085/R089. GET /v1/karaoke/search(brand TJ/KY, kind TITLE/ARTIST/NUMBER 기본TITLE, q), 기존 bearer·기기 인증 사용. 성공/ApiException 오류 Cache-Control:no-store. 중복/미지 조건·잘못된 브랜드 거부, 다른 메서드 deny.
- 응답 results에 brand/number/title/artist/provider/source_ref/source_token/expires_at/matched_song_id 제공. 앞 어댑터·계정 제한과 연결. 현재 인증 계정 ACTIVE/TJ/정확한 문자열 번호만 한 SQL 조회로 연결하며 금영은 null. 제목/가수·괄호로 병합하거나 버전 추론하지 않음. 조회 뒤 세션 재검증. 결과/개인 연결 캐시 없음.
- SourceTokens는 독립32byte 서버 키 + AES-GCM, 별도 AAD/랜덤IV/canonical Base64/크기 제한/미래 발급 거부, provider/brand/number/원본/출처/발급·만료 고정24h 인증. 계정 접근 권한을 대체하지 않음. 서버 재시작 임의 키/기본 키 사용 없음. songrecord.karaoke.key-base64는 배포 환경의 비밀 설정으로 주입하며 비어 있으면 검색503 SEARCH_SIGNING_UNAVAILABLE, 외부 호출 이전 fail closed. 실제 운영 키를 테스트 키로 대신하지 않음. 키 설정과 P00 제공자 조건 확인은 배포 전 필요.
- 일괄 API test bootJar 종료0 BUILD SUCCESSFUL57초, XML632: 성공552/실패0/오류0/MySQL skip80. 현재 모델 검토에서 만료 시각의 ms 정밀도 일치 보완 후 *karaoke.* test bootJar 종료0/10개 성공. 전체 관련 회귀+새 시각 경계, 실제 HTTP 직렬화/인증·method 제한/no-store/빈 결과·금영null/H2 임시 DB의 타계정·삭제곡 제외 검증. 사용자 DB 초기화 없음.
- 현재 모델 별도 검토: 원본 필드/브랜드/번호/원본 보존·출처 암호화/시각·계정 격리·검사 결과·기존 후보 회귀 대조, 정밀도 지적 해결. 새 사용자 실기 없음. P15-04에서 실제 검증기를 기존 등록 경로에 연결하고 만료 TJ 재조회 적용 예정.
- 최종 SHA/필수 CI는 푸시 뒤 대조. 모델 관측 gpt-6.1-sol, 요청medium/로그 추론 수준 관측 없음. 개념: 출처 토큰은 검색 후보가 변조되지 않았다는 근거이며 사용자 계정 접근 권한과 별개.

## CI 차단 — ENV-GITHUB-ACTIONS-ACCOUNT-01
- SHA ee190a67c899d1501ef9c078d7d2a2c22ff63e44, CI37927600916/Idempotency MySQL37927601018 실행 전 failure. GitHub는 최근 계정 결제 실패 또는 지출 한도 증가 필요를 안내. 실패 원인 둘 중 무엇인지는 계정 화면 확인 전 미확인. runner/steps 없음, 로컬 코드 검사의 실패로 합산하지 않음. 무료 한도 소진이라고 단정하지 않음.
- 로컬 전체632(552 성공/80 MySQL skip), 검토 보완 관련10 통과 유지. GitHub 차단을 무시해 완료 처리하거나 P15-04로 우회하지 않음. 임의 환경 반복/모델 상향 없음. 현재 P15-03 진행/측정 종료하지 않음.
- 미커밋: 기존 사용자/워크플로우 기록과 P15-01~02 완료 footer·진행·상태·직접 할 일·본 CI 차단 근거. 제품 코드 변경은 위 SHA로 커밋·푸시됨. 현재 제품 실행/CI 감시 없음, 로컬 사용량 최종 집계 프로세스는 제품 실행과 구분.
- 담당/재개: USER-058 사용자가 ksh321 무료 Actions 사용량·초기화/결제 실패 상태 확인, AI가 이후 동일 P15-03 원격 검사 재실행·필수 성공 확인→finish03→begin04. CI 우회·추가 결제·한도 상향·공개 전환 없음. 폰 알림 전 직접 행동 안내 저장.

- USER-058 Intervention 알림 ntfy 서버 접수, 실제 폰 수신 미확인. Billing 화면 열기 요청 queued이며 렌더 관측 없음. 종료 전 선택기 WAIT; ready/running 각0, 현재 P15-03의 환경 차단을 pending+blocker+재개 조건으로 저장. 직접 할 일1건.

## 2026-10-09 공개 전환 후 CI 재실행

무료 Actions 분 소진 원인을 확인하고 사용자 승인으로 ksh321/Song_Record를 public으로 전환했다. 익명 조회 성공, 소유자 외 쓰기 계정·대기 초대·배포 키 각각 0. 검사한 remote main은 ee190a67c899d1501ef9c078d7d2a2c22ff63e44 그대로다. run 37927600916·37927601018의 재실행 요청 후 queued 확인. 완료 판정은 같은 SHA의 필수 CI 최종 결과 확인까지 대기한다. 비밀값 없는 공개 권한 검증 기록은 Git 제외 .local/workflow/public-safety/access-after.json에 보존한다.

## 최종 완료
- 최종 SHA ee190a67c899d1501ef9c078d7d2a2c22ff63e44, 필수 CI 37927600916, 37927601018 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
