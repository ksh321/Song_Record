# P15-05 검색 화면 연결 (원수)

- 선행 P15-04 0029591e32bbeab3381d9d079218007ec9061c94, CI37939608067·37939607831 PASS 및 알림 서버 접수 확인 후 finish04→begin05. 요청 gpt-6.1-sol/medium 고정.
- 원본 계획759~761, R083/R089/V40. UI_REFERENCE·팔레트·HTML의 최종 검색 패널(1134~1147), 기존 앱 테마·탭·ContentState 사용. 기존 준비 검색 탭에 실제 인증 GET 검색을 연결했다.
- TJ/금영, 곡명/가수/번호, trim·선행0 유지, 입력400ms 지연. 조건을 바꾸는 순간 요청 ID를 올려 새 요청 전 대기 중에도 이전 성공/실패가 상태를 덮어쓰지 않는다. 정상빈결과·실제 로딩·제공자 오류를 구분, 장애에는 입력을 유지한다.
- 인증 세션·기기 헤더, HTTPS 및 debug dev의 고정 loopback 허용, redirect 금지·응답 크기/시간 제한·브랜드/번호/원본/출처 검증. 인증/로그아웃·계정 변경 및 dispose 시 오래된 결과 배제. 토큰은 출력하지 않으며 결과 객체 toString은 REDACTED.
- 수정: features/search의 상태·HTTP·화면, app_shell/searchBuilder 및 SongRecordApp 인증 연결. P15-06의 KY→TJ 문맥과 P15-07 직접 등록 진입은 아직 후속이다.
- 현재 모델 별도 검토: 입력과 응답ID 비교·같은 브랜드·취소·계정 전환·기존 탭/녹음 패널·클라이언트 통신 제한·테스트 대조. 종료 기준은 전체 Flutter 검사/분석/APK 및 정확 SHA의 필요한 CI.
- 문제별 기록: P15-05-COMPILE-LIST — 첫 검사에서 HTTP 반환 List<dynamic> 추론 문제 발견, 명시적 List<KaraokeCandidate> 적용 후 검색전용6개 PASS. P15-05-LINT-FORMAT — 분석의 import 정렬/if중괄호6개 지적, 범위 제한 정리. 다른 원인을 합산하거나 모델 상향 횟수로 혼합하지 않음. 초기 원시 로그는 Git 제외 .local/workflow/p15-05에 보존.
- 실기: 전체 검색 연동을 P15-08 설치본으로 검증한다. 이 번호에서 아직 사용자 폰 결과를 통과로 주장하지 않는다.
- 개념: 입력이 바뀌는 순간 응답 자격을 취소해야 입력 지연 시간 동안 오래된 결과가 나타나는 문제도 막을 수 있다.

- 최종 일괄 검사: Flutter852개 성공(81초), analyzer 지적0(3.5초), debug dev APK SUCCESS. 검토에서 인증 갱신 도중 계정 변경의 요청 전 경계 추가→앱탭·검색·HTTP 영향10개 PASS, 최종 analyzer 지적0(3.4초), 현재 소스 APK SUCCESS17.2초. 현재 모델 재검토 지적 없음. 새 원격0029591e 기준 전체 변경 영향은 Flutter CI만 필요.
