# P14-01 로컬 파일 검증 조회 (원수)

- 범위: 원본 코드구현계획서 v1.0 P14-01(p00718~720), 구현설계서 v1.11 2.5·8.4, R032/R074 및 D04 현재 기기 실제 파일 규칙.
- 선행: P02/P09/P12 완료 근거 유지. 승인 P14-01~08 순차, 이번 변경은 P14-01.
- 모델: 사용자 고정 요청 Sol6.1/medium, 실제 turn_context gpt-6.1-sol/medium. 추가 모델/에이전트 호출 없음.
- 변경: AccountStore.findPlayableLocalAudio가 계정별 DB의 완료 파일 경로·크기·SHA-256을 실제 디스크와 대조하고 LocalAudioLookup이 현재 기기 소스를 제공한다. 다른 기기 보고·서버 보관 여부는 이 API의 입력이 아니다. 기존 완료 파일 읽기는 읽은 바이트 길이까지 검사한다.
- 파일: apps/mobile/lib/core/audio/local_audio.dart, core/database/account_store.dart, test/local_audio_test.dart.
- 현재 모델 별도 검토: 원본/D04와 diff·검사 대조. 계정 전환은 manager 직렬 실행 앞뒤 및 호출부 requireActive로 늦은 결과를 차단한다. 계정 경로의 링크·탈출 검사 재사용. 확인된 없음/손상은 null이며 권한·기타 I/O 오류는 예외를 유지해 UNKNOWN과 부재를 혼동하지 않는다. 파일·DB를 삭제하거나 손상 원본을 교체하지 않는다. 경로는 조회 시점 검증이며 실제 재생 전 재조회는 P14-03에서 연결한다.
- 로컬 검사: flutter test --no-pub --reporter expanded → 818개 PASS(75초). 실제 임시 디스크/SQLite에서 없음·정상·같은 크기 손상·삭제·다른 계정·동일 계정 재로그인 대조. flutter analyze --no-pub → No issues found(8.7초). 검토 후 I/O 오류 분류 보강은 local_audio_test 1개 PASS 재검증. 잘못된 프로젝트 경로에서 1회 명령 실행은 pubspec 부재로 시작 전 실패했으며 올바른 mobile 경로로 재실행했다.
- 필수 실기: 이 단계는 파일 조회 내부 경계이며 실제 디스크 회귀를 수행했다. 기기 재생/내보내기 동작은 P14-03/P14-06의 실기 범위로 별도 확인하며 기존 P13 실기를 새 재생 실적으로 계산하지 않는다.
- 원격 기준: fresh ls-remote main a1be3019dfb27cb3eb30c96d89dc4eb5becfe638. 최종 SHA Flutter CI 대기. 코드 구현만으로 완료 아님.
- 학습: 메타정보에 파일 경로가 남아 있어도 실제 파일의 바이트가 일치해야 현재 기기 파일로 인정한다.
