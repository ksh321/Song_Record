# P13-04 정리 확인 토큰 (원수)

- 원본 계획 p00693~694, 설계의 15분 보존 확인·cleanup_fence, R060/V18 대조. P13-03 c99c1b65d9508f4949046a4513583cc3c087b0e0 필수 CI PASS 후 finish→begin. 요청·관측 Sol6.1/medium 고정.
- CleanupConfirmations/Controller 및 OpenAPI: 인증 계정·recording·현재 STORED generation·SHA256·cloud_revision에 묶인 임의 UUID 토큰. 최대 20개 preview, 최초 발급부터 15분이며 반복 요청은 기간을 연장하지 않는다. confirm은 동일 기기·해시·유효 기간·현재 객체·최신 보호 역할을 다시 확인한다. LOCAL_VERIFIED와 명시적 USER_CONFIRMED_LOSS를 구분하며 앱은 손실 승인을 자동 전송하지 않는다.
- confirm만으로 DELETING 전환·R2 삭제·used 차감을 하지 않는다. 실제 삭제 직전 재검사는 P13-05, 객체 삭제 확정은 P13-06 범위다. 영수증 재전송의 과거 성공 응답도 후속 삭제 권한 재검사를 대체하지 않는다.
- AccountStore/LocalCleanupCoordinator/HttpCleanupTransport: 실제 영속 파일 해시·크기 확인 후 HTTP 전송 전에 PREPARING 토큰과 cleanup_fence를 원자적으로 저장한다. 응답 유실·앱 재실행·로컬 시각 만료만으로 보호를 해제하지 않는다. 인증 서버의 같은 token/generation에 대한 terminal 결과만 정확히 한 번 해제 가능하다. 계정 guard·인증·리다이렉트 금지·응답 크기/시간 제한·민감 값 미출력 유지.
- 로컬 DB 10→11은 새 토큰 테이블만 추가한다. 이전 1~9 및 10의 실제 파일·오프라인 정보·기존 cleanup_fence=2 유지 확인. 원본 스냅샷1~10 보존, LF SQL로 v11 및 코드 생성.
- 일괄 로컬 검사 check-local.ps1: 서버 test/bootJar PASS55초(XML603, 실패0/오류0, 조건부76). 계약 PASS7 wire/141 boundaries. analyze PASS3.6초. Flutter 전체805 PASS/9 FAIL: 9개 모두 기존 마이그레이션 테스트의 버전 기대값10과 실제11 불일치. 기대값을 신규11로 정확히 수정했으며 데이터 보존 검사는 유지했다. 수정 영향 및 추가 HTTP 검사 포함 review-mobile.log 15개 모두 PASS6초. 나머지 전체 검사805개 통과 근거 유지. review-analyze PASS4초. preservation APK PASS22초.
- 서버 검토 후 generation 변경에 대한 이전 토큰 거절 검사 추가, CleanupConfirmationTests 재검사 및 bootJar PASS15초. 토큰 만료·다른 계정·해시·revision·generation 불일치·명시적 손실 승인 누락·중복 확인·used 미차감 대조.
- 현재 모델 별도 코드 검토: 원본 완료 조건·diff·실행 결과·USER_SYNC와 asset 잠금 순서·owner 범위·토큰 기간·보호 역할·실제 파일 확인·영속 fence·응답 유실·schema 이전·원본 보존·민감 값 출력 대조 완료. 테스트 기대 버전 및 SQL 줄바꿈 지적 해결. 별도 모델 호출 없음.
- 이 항목은 서버 토큰 및 영속 DB 경계 검사이며 새 폰 조작 요구 없음. P13-03의 실제 Android 파일 검사6개 사용자 통과는 보존하되 P13-04 실기 결과로 재명명하지 않는다. 삭제 작업·terminal 조회 연계 및 전체 교차 경합은 후속 원본 P번호에서 검증한다.
- 커밋·푸시 뒤 현재 SHA 필수 CI 대기. 로그 .local/workflow/p13-04/, 비밀·원본 오디오 없음.
- 학습: 요청을 보내기 전에 로컬 보호를 영속 저장해야 응답이 없어도 마지막 사본을 지킬 수 있다. 토큰의 유효 기간과 로컬 보호의 해제 조건은 다르다.

- 원인 P13-04-JDBC-TIME: 실제 MySQL JDBC는 DATETIME을 LocalDateTime으로 반환하며 H2는 Timestamp를 반환해 강제 형변환이 실패했다. 최초 CI 37878841230에서 확인. UTC 변환을 두 타입 모두 지원하도록 수정1회, 타입 동등성 회귀 및 CleanupConfirmationTests/bootJar PASS9초. 로컬 Docker 엔진 미실행으로 실제 MySQL 로컬 검사 불가, 필수 원격 MySQL로 재검증. 기존 푸시 이력 재작성 없음. 최종 SHA에서 작업 전체 영향 검증을 위해 CI와 계약 workflow_dispatch 사용; 기존 앱/계약 변경이 최근 서버 수정 커밋에 가려지지 않도록 최초 push 전 BaseCommit c99c1b6 유지.

- 같은 시간 변환 검토에서 SQL DATETIME 쓰기도 JVM 시간대에 의존하지 않도록 UTC LocalDateTime으로 고정. Timestamp는 DATETIME의 UTC 벽시각으로 읽는다. 기본 JVM 시간대를 Asia/Seoul로 바꾼 전체 토큰 시나리오 및 타입 동등성 검사 PASS9초(utc-write-review.log). 기존 UTC CI 외의 노트북 시간대도 확인. 별도 근본 원인 실패 횟수 초기화 없음.
