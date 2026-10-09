# P14-04 파일 다운로드 (원수)

- 사용자 승인 P14-01~08 순차, 현재 gpt-6.1-sol/medium 고정·현재 대화 직접 구현/별도 검토. P14-03 dbf4fc01ff98f88bbf2312715456737dcce0f9f0 필수 CI 37906497384/37906497365 PASS 유지.
- 원본 계획서 P14-04 p00727~729/R075: 임시 다운로드→크기·체크섬 검증→계정 영속 경로→동일 Recording UUID DB 연결, 녹음 메타정보 생성하지 않음. 실제 설계서 v1.11 해시 일치 확인, 8.4 p503~505 및 D04 현재 기기 실제 파일 기준 확인.
- RecordingDownload는 로컬 정상 사본을 우선 반환한다. 없으면 P14-02 소유/lifecycle/STORED 게이트가 있는 playback URL과 객체 식별자를 받고 현재 계정/UUID/5분 유효시간을 확인한다. 수동 다운로드가 보관 역할 선정에 잘못 종속되지 않도록 기존 preservation-url 대신 내부 playback URL을 사용한다.
- HttpSignedAudioDownload는 최대6MiB/예상 길이/30초, 리다이렉트 금지, API 인증·기기 헤더를 객체 GET에 전달하지 않는다. 원본 ticket의 크기·해시·세대에 연결해 기존 LocalPreservation의 파일/DB 경계를 재사용한다. 문자열 오류는 고정 메시지로 URL을 내보내지 않는다.
- account_store preserveDownloadedAudio의 임시 파일 검증을 rename 이전에 추가. 저장 후에도 기존 영속 크기·해시 검증 유지. 다른 내용의 원본이나 cleanup_fence 사본은 교체하지 않으며 실패 임시 파일만 정리한다. 같은 Recording UUID의 local_recording_files만 갱신, 메타정보와 저널/입력 생성·삭제 없음.
- 일괄 로컬: 기존827 PASS, 새4 테스트가 시험 설정 원인으로 실패. 원인별 분리: (1) 테스트 임시 디렉터리 제공 누락1회 (2) Widget binding의 HTTP400 모의와 실제 HTTP 시험 충돌1회. 제품 동작 실패 횟수로 합산하지 않음. HTTP 시험을 별도 파일로 분리해 실제 loopback GET·헤더·리다이렉트·길이를 유지하여 기대값/검사를 약화하지 않음.
- 영향 재검증: recording_download 3/HTTP1 + 기존 preservation/HTTP/audio 총14 PASS (2초), analyzer No issues found (4.5초), preservation APK SUCCESS (27.9초). 전체 최종 SHA CI는 아직 실행하지 않음.
- 별도 현재 모델 검토: 원본 완료 기준·실제 diff·검사 결과·데이터 보존 대조. metadata 생성 없음, 정상 사본의 중복 다운로드 없음, 잘못된 크기/해시/계정의 영속 연결 차단, 인증 헤더 미전달, 임시 검증 선행, 기존 파일/펜스 보존 확인. 사용자 고정 모델 유지, 다른 모델/에이전트 호출 없음.
- 실기 준비: 합성 UUID 계정의 실제 dev R2 GET→폰 영속 파일→같은 UUID→메타정보 미생성→URL API를 사용 불가로 둔 실제 native 로컬 재생. 별도 APK update install Success, 앱 시작 요청까지 완료했으나 확인 시 systemui 잠금 화면 및 adb device not found 관측. 실제 통과 결과는 미확인. 원인은 연결/잠금 관측까지만 기록하고 추정하지 않음.
- AI 자동 검사를 위해 USER-055 USB 연결·잠금 해제만 요청. 소리·버튼 조작 재요청 없음. dev 합성 fixture PID23760 READY, loopback46414 최대45분 후 자기 시험 객체 정리. 실제 연결 뒤 프로세스·검사 결과·정리를 대조한다.
- 현재 미커밋 변경 보존. 필수 폰 파일 검증 대기 때문에 커밋/푸시·다음 P14-05~08을 실행하지 않음. 원격 fresh base dbf4fc01ff98f88bbf2312715456737dcce0f9f0.
- 관련 개념: 네트워크 수신 성공은 영속 파일 검증과 DB 연결 성공이 아니다. 검증된 파일을 같은 식별자로 연결해야 중복 녹음이 생기지 않는다.

## 실제 설치본 검사 통과
- USER-055 회신 후 device 확인·USB reverse 복구. 검증 앱만 데이터 유지 재실행하여 실제 UI에서 ‘P14-04 실제 R2 다운로드·계정 영속 파일·같은 UUID·메타정보 미생성·오프라인 native 재생 5개 통과’ 확인. 기존 사본 재사용이 아니라 신규 실제 GET 표시를 대조. 사람의 소리 확인은 P14-03 완료 근거이며 이번에는 native playing/pause를 AI가 검사.
- 시험 fixture 종료204 후 CLOSED/시험 객체 정리 확인 예정. 사용자 행동 0건. 현재 소스의 검토 지문 유지, 필수 CI 대기.

- fixture CLOSED 확인: 자신이 생성한 합성 객체 삭제·없음 대조 완료.

## 최종 완료
- 최종 SHA 99cbe0394ea012ed868da7333a632e6caa4102f0, 필수 CI 37910214758 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
