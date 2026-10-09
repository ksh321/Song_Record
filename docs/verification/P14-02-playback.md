# P14-02 서버 재생 URL (원수)

- 원본: 계획서 P14-02 p00721~723, 설계서 8.4 및 12.5 p00898~900, R074/R119. 승인 범위 P14-01~08 순차이며 P14-01 최종 CI 완료 유지.
- 요청·관측 모델: 사용자 고정 gpt-6.1-sol/medium, 단일 현재 대화 구현 및 별도 검토.
- 변경: playback.PlaybackController/PlaybackUrls, OpenAPI 실제 POST /recordings/{id}/playback-url. 인증 세션을 조회 전·서명 후 다시 검사하고 같은 계정 ACTIVE 녹음의 STORED 세대만 허용한다. 서버가 계산한 owner/recording/generation 객체 키·크기·해시·revision을 검증하며 클라이언트 객체 키를 받지 않는다.
- 응답: URL·만료·소유 객체 식별자, Cache-Control no-store. R2GetSigner 기존 SDK 서명 재사용, 정확히 300초. 타인·삭제·미보관은 AUDIO_UNAVAILABLE이며 URL 없음. 발급 후 삭제/로그아웃 시 이미 발급한 주소가 만료까지 살아 있을 수 있음을 원본대로 계약에 명시. 공개 공유 기능 아님.
- 일괄 로컬: Gradle test bootJar --offline → 621개 중 계약 등록 목록1 FAIL, 80개 MySQL 환경 미실행, 나머지540 PASS(54초). 새 실제 controller를 계약 검사 목록에 추가. 검토 보강 테스트의 Mockito 재스텁은 테스트 설정 자체1회 FAIL 후 doReturn 방식으로 수정. 두 원인 분리, 제품 보안 동작 실패 아님.
- 영향 재검증: PlaybackUrlsTests4/R2GetSignerTests1/ApiContractTests5 총10 PASS, bootJar SUCCESS(7초). 실제 SDK로 네트워크 없이 합성 키의 5분 GET 서명·비밀값 미노출 확인. OpenAPI/security/wire7/schema141 검사 PASS.
- 별도 현재 모델 검토: 원본 완료 기준·diff·실행 결과 대조. 현재 사용자·녹음 수명·STORED 모두 같은 조회에서 확인, 객체 키 혼동 차단, 만료/로그아웃 전후 재검증, 기존 보존 다운로드의 계약은 변경하지 않음. 녹음 정보·보관 역할·사용량·실제 R2 객체 변경 없음.
- 실기: 이번은 서버 URL 발급 경계이며 실제 기기 플레이어는 P14-03에서 확인. 과거 R2 PASS를 이번 실기 통과로 기록하지 않는다.
- 원격 범위 기준: fresh main 54be7f0186dbdffb68ecefd302865bef99108608. OpenAPI 영향에 따른 전체 필수 CI(Flutter/API/MySQL/contract) 대기. 로컬 MySQL skipped는 PASS 아님.
- 관련 개념: 서명 주소는 짧은 접근 권한이며 서버에서 회수해도 이미 발급된 URL의 즉시 무효화를 보장하지 않는다.

## 최종 완료
- 최종 SHA 50d5835fca91f014a4bd31e1ab29e2ccf6d135a3, 필수 CI 37900400289, 37900400274, 37900400385 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
