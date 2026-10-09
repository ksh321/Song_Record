# P15-04 후보 재검증 연결 (원수)

- 선행 P15-03 ee190a67c899d1501ef9c078d7d2a2c22ff63e44의 공개 전환 후 같은 SHA CI37927600916·37927601018 PASS, 폰 알림 서버 접수 확인. finish03→begin04. 사용자 고정 요청 gpt-6.1-sol/medium; 실제 추론 수준 관측은 별도.
- 계획서 원본 문단756~758, 요구사항 R085/R084, P08 후보 검증 경계 연결. 운영에서는 P15 SourceTokens와 Manana NUMBER 조회를 사용하며 dev+candidate-fixtures만 기존 합성 검증 유지, production 금지 유지. 키 미설정·구성 누락은 fail closed.
- 만료 TJ 토큰은 인증된 원래 번호 문자열(선행0 포함)로 같은 브랜드만 재조회, 정확 일치 하나만 수락. KY·변조·다른 번호/빈 결과는 등록하지 않는다. 원본 갱신은 제공자 값에서만 받고 제목의 버전을 추론하지 않는다. 재조회는 기존 계정별 검색 제한·3초 제공자 제한을 사용한다.
- 등록은 외부 조회를 트랜잭션/DB 잠금 이전에 수행하고 실제 변경 전 계정·유효기간을 다시 확인한다. 같은 계정/op 성공 영수증은 재조회 없이 기존 응답 재현, 다른 본문 충돌 유지. 재조회 장애에는 DB 변경/영수증을 만들지 않고 같은 키로 재시도 가능하며 요청 입력을 소비하지 않는다. 앱 초안 보존은 기존 등록 흐름을 유지하고 P15-07/08에서 화면 대조한다.
- 수정: LiveCandidates, CandidateVerifier/Configuration, TjCandidates, SongCreation, IdempotentMutations, KaraokeConfiguration 및 후보/멱등 회귀 테스트. 현재 구현된 곡 등록 경로에 적용. Purpose.PLAYLIST 경계의 금영 금지는 유지하며 실제 목록 추가 API 연결은 원본 후속 P19 범위를 새로 구현한 것으로 주장하지 않는다.
- 첫 일괄 ./gradlew.bat test bootJar --no-daemon --console=plain 종료0: XML638, 성공558, 실패/오류0, MySQL80 skipped. 현재 모델 별도 검토에서 검증기 두 Bean의 선택 모호성 발견→Primary 명시+실제 구성 회귀 보강. 수정 영향 재검증 진행 중. 필요한 MySQL 검사는 정확 최종 SHA CI에서 수행한다.
- 실기: 이 서버 내부 연결에 별도 사용자 폰 조작 없음. 검색 화면 연동 후 P15-08 설치본 실기 필요. 배포용 비밀 설정과 제공자 이용조건(P00)은 기존 배포 전 조건 그대로 유지.
- 개념: 외부 재조회와 DB 변경을 분리하면 외부 장애가 데이터 잠금을 길게 잡지 않으며, 성공 영수증은 재조회 장애와 무관하게 재현할 수 있다.

- 검토 보완 영향 재검증: test (*CandidateTests/*LiveCandidatesTests/*IdempotencyTests/*SongCreationTests) bootJar 종료0 BUILD SUCCESSFUL25초, XML {'tests': 97, 'failures': 0, 'errors': 0, 'skipped': 45}; 기존 MySQL 조건은 CI에서만 충족. 수정 후 현재 모델 재검토: 실제 구성 선택·토큰/번호/원본·계정 재검증·잠금 밖 재조회·재실행 본문 충돌·회귀를 대조, 남은 코드 지적 없음.

- 푸시 시 GH007 이메일 보호 거절은 코드 실패가 아니다. 이번 미푸시 커밋 b64af70은 로컬 codex/p15-04-before-email-fix에 보존하고 공식 계정 noreply 작성자로만 정정했다. 서버 이메일 보호 설정·기존 푸시 이력은 유지. 최종0029591e32bbeab3381d9d079218007ec9061c94 일반 main 푸시 성공, 기준ee190a6의 필수 CI 감시PID21188 시작.

## 최종 완료
- 최종 SHA 0029591e32bbeab3381d9d079218007ec9061c94, 필수 CI 37939608067, 37939607831 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
