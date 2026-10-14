# P24-09 스토어 제출 준비 — 사용자 확인 대기

- 선행 P24-08 SHA 442f26c (전체 SHA는 최종 Git/CI 기록), 문서 범위 NOT_REQUIRED 확인 후 원수 시작. 요청/관측6.1 Sol/medium. 원본 계획 p01060–01061, R124·개인정보/삭제 계약.
- 변경: Android build.gradle.kts에서 release의 debug 서명 대체 제거, 보호된 외부 properties 업로드 키 구성, 키 미등록 prodRelease 패키징 차단. 기존 debug 앱과 설치 데이터를 바꾸지 않음. 키/암호를 소스·명령·로그에 넣지 않음.
- SDK: 설치 FlutterExtension compile36/target36/min24 확인, 현재 공식 Google Play 신규 모바일 앱 기준 API36. Manifest RECORD_AUDIO/마이크 foreground서비스/비공개 서비스 확인. P18 실제 시작/권한/알림 종료 근거 보존, 이번에 재검사 통과를 만들지 않음.
- 개인정보·데이터 보안·삭제·외부 처리 대조와 공식 출처는 docs/runbooks/store-submission.md. localhost를 공개 삭제 URL이라고 하지 않는다. 운영 worker 현재 비활성·공개 OAuth/배포 미수행. 사용자 ZIP은 일반 파일, 서버 백업 암호화와 구분. D12의 무료 서비스 이용조건 확인 유예를 유지하되 제공자 허가로 표현하지 않음.
- 실제 검사: Gradle bundleProdRelease --dry-run은 업로드 키 없이 의도한 고정 오류로 차단 PASS. assembleDevDebug --dry-run PASS, 실제 assembleDevDebug 종료0/BUILD SUCCESSFUL,197 task(41실행156up-to-date). Kotlin DSL Properties 이름 충돌1회 수정 후 두 구성과 실제 빌드 통과. SDK/플러그인 deprecation 경고는 빌드 실패가 아님.
- 별도 현재 모델 검토: task graph의 prodRelease 패키징 경계, 무서명 우회 방지, debug 회귀, 속성/키 미등록 fail-closed, 실제 정보와 표시 내용 대조. 추가 모델 호출 없음. 실제 업로드 키 등록·서명된 출시 AAB·Play 제출 PASS는 없음.
- 사용자 ‘Play 계정 아직 없음’ 확인. 신규 유료 계정/결제 미수행. USER-100은 최종 공개 개인정보 문서의 게시자·문의 이메일 확인 대기, 폰 알림 서버 접수·수신 미확인. 이 회신 없이 완료 처리하거나 P24-10으로 우회하지 않음. 공개 웹 게시·스토어 제출은 별도 승인 범위.
- 커밋/정확 SHA 필수 CI 결과 확인 대기. 이미 완료된 P24-05–08/USER-099는 유지.

학습 개념: 개발 APK 빌드 성공은 출시 서명·공개 개인정보 URL·실제 계정 삭제 운영 연결의 통과를 뜻하지 않는다. 제출 준비의 미확인 조건을 공개 표시와 분리해 추적한다.
