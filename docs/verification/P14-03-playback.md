# P14-03 플레이어 연결 (원수)

- 승인 범위 P14-01~08 순차. P14-01/02 최종 완료 유지. 현재 모델 사용자 고정 gpt-6.1-sol/medium, 현재 대화 직접 구현·별도 검토.
- 원본 계획서 p00724~726: 재생·일시정지·탐색·완료·실패 및 만료 재발급, 오프라인 완료 로컬 재생, 실패 시 입력·파일 보존. 관련 설계 8.4/12.5, R074/R119와 계정 파일 계약 대조.
- 변경: core/audio AudioPlayback·AndroidAudioPlayer·HttpPlaybackUrls·PlaybackTicket, Android PlaybackBridge 및 MainActivity 연결. 실제 계정 파일 크기·해시 재확인 후 로컬 우선 재생. 원격은 같은 계정/녹음의 HTTPS R2 5분 GET URL만 사용. 인증 헤더는 API에만 전달하며 R2로 전달하지 않음. 세션·요청 세대 검사가 늦은 응답과 계정 전환을 차단한다. 실패/재생 기능은 DB·파일 삭제 권한이 없음.
- 만료는 일시정지 재개/재생 실패 때 새 URL 1회 발급 후 이전 위치를 복원한다. 반복 오류는 실패 상태로 종료. native prepare 30초, API 시간/응답 16KiB 제한. 현재 모델 검토에서 이벤트 스트림 오류 시 플레이어 정지, 늦은 native 오류/준비 콜백이 새 플레이어를 중단하지 않도록 보강.
- 실제 R2 검사에서 기존 dev.api의 최종 GET 403 확인. 임시 업로드 전용 권한은 올바른 기존 정책이므로 확장하지 않았다. 별도 dev.playback 최종 읽기 전용 역할·명시적 설정을 추가. API/worker 키 폴백 금지, reader의 PUT/최종 쓰기 차단. dev.worker의 합성 시험 객체만 만들고 검사 후 정리. 기존 사용자 객체·운영 버킷 조작 없음.
- USER-053 사용자 최초 등록 완료. DPAPI 역할 바인딩·등록 PASS. dev.final ALLOWED, dev.temporary/prod 양쪽 및 쓰기 양쪽 DENIED. 실제 signed GET 바이트 일치 및 시험 객체 정리 VERIFIED. 키는 메모리/자식 stdin으로만 전달, 로그/CLI/환경변수/Git에 없음.
- 자동 검사: Flutter 전체 827 PASS (70초). 초기 analyzer 형식/불필요 비교 지적 수정 후 No issues found (3.4초). R2 도구 16 PASS (0.229초). 현재 diff 공백 검사 PASS. 후속 영향 검사 및 서버/APK 결과는 아래에 기록한다.
- 실기 준비: 별도 preservation 앱, 합성 12초 AAC-LC 음원, 계정 격리 INPUT_PENDING 원본과 저널을 사용한다. dev R2 읽기/실제 Android MediaPlayer를 시험한다. USB 로컬 API fixture는 고정 합성 토큰/녹음만 허용하며 제품 인증 서버 자체의 실기라고 주장하지 않는다. 인증/소유/lifecycle 실제 서비스 경계는 P14-02 테스트 근거를 유지한다. fixture는 loopback만 열고 45분 종료 또는 명시적 종료에서 자신이 생성한 객체만 정리한다.
- 만료 실기는 클라이언트 시각을 6분 모의하여 5분 대기만 줄이고 실제 새 R2 URL로 재생을 확인한다. 실제 서버 만료 시간은 SDK 테스트 300초, 실패/위치복원은 자동 테스트도 확인한다.
- 필수 사람 확인: 실제 소리, 정지·다시 재생·탐색·완료, 실제 R2 재생, 모의 만료 재발급, 실패 후 원본·입력 보존. 아직 사용자 실기 결과 미확인으로 완료/푸시하지 않음. 이후 커밋·정확한 SHA 필수 CI 대기.
- 관련 개념: 로컬 파일 존재와 재생 가능 형식은 별개다. 재생 실패는 녹음 원본 삭제 이유가 아니다. 읽기 URL 서명과 실제 버킷 읽기 권한도 별개이며 둘 다 검증해야 한다.

## 설치본 검사 대기
- 영향 재검증: 모바일 9 PASS (1초), analyzer No issues found (3.4초), Android preservation APK SUCCESS (57.1초).
- 서버 전체: 623 tests, failures0/errors0, 80 MySQL 환경 skipped, 543 PASS. bootJar SUCCESS (64초). 미실행 MySQL은 통과 아님이며 이후 정확한 SHA 원격 검사가 필요함.
- 폰 R5CW618VA1M update install Success, 실제 화면 제목·준비 완료 확인. 고정 합성 API 응답 소유/녹음·HTTPS 확인 PASS, fixture READY. 서버 PID16548, loopback46414, 최대45분 후 합성 객체 정리하며 강제 종료하지 않음. 사용자가 늦게 회신하면 실제 프로세스/객체 상태를 먼저 확인한다.
- USER-054 네 항목 실기 회신 대기. 현재 미커밋 변경 보존, P14-04~08 미착수.

## 사용자 실기 통과
- USER-054 ‘다 성공’ 회신으로 안내한 네 항목 모두 통과. 이전 미확인 문구는 이 회신으로 해소. 현재 소스·설치 APK 이후 변경 없음. 필수 CI는 아직 미확인.

- 合成 fixture 明示 종료204 후 CLOSED 확인: 생성한 시험 객체 삭제·없음 확인 완료. 원격 최신 main/BaseCommit 50d5835fca91f014a4bd31e1ab29e2ccf6d135a3.

## 최종 완료
- 최종 SHA dbf4fc01ff98f88bbf2312715456737dcce0f9f0, 필수 CI 37906497384, 37906497365 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
