# P18-02 녹음 완료 → 입력 대기 상태 연결

## 범위·근거
- 원본 계획서 v1.0 p00837~39: P02 journal, 검증된 파일 spec, 계정 DB 입력 대기/DRAFT 및 전송 큐 연결. 앱 종료 후 재진입해 완료 파일·입력 대기를 찾는다.
- 구현설계서 v1.11 p00314~18, R006/R008/R036, 기존 P09-01 metadata-only RecordingDraftCreate 계약·MutationRequest whitelist를 재사용한다. 파일 spec은 로컬 journal에 보존하며 CREATE에 미지원 file 필드를 보내지 않는다.
- 승인 범위 P18-10, 원수 요청/실제 관측 gpt-6.1-sol/medium. 이전 P18-01 실제 3개 검사 통과는 유지하고 반복하지 않는다.

## 구현·검토
- Android 완료 journal의 UUID·계정·경로·길이·SHA256·실제 AAC-LC/48k/mono probe를 확인한 bytes만 Dart 계정 저장소로 넘긴다. 새 journal에는 녹음 시작 시각·시간대·당시 offset도 기록한다. 과거 journal의 미기록 시간대는 UTC/0로 보존하며 당시 지역 시간대를 추정하지 않는다.
- 계정 저장소의 기존 파일 보존·saveEdit·journal 처리를 private 공통 메서드로 재사용하여 하나의 계정 lease와 외부 DB transaction에서 파일 인덱스·DRAFT·metadata CREATE 큐·COMMITTED journal을 함께 확정한다. schema 변경 없음.
- 실제 bytes 길이·checksum을 재확인하고 flush/rename 후 DB 기록을 확정한다. DB 실패 시 DB 전체가 rollback되고 native original/journal 및 이미 보존한 파일은 삭제하지 않아 재시도할 수 있다. 파일 시스템과 DB가 하나의 원자 저장이라고 주장하지 않는다.
- 완료 UI handoff는 single-flight, 실패 시 수동 재시도와 완료 재생을 유지하며 handoff 성공 전 새 녹음으로 native journal을 덮지 않는다. 동일 UUID 재진입은 기존 편집/SAVED를 덮어쓰거나 CREATE를 다시 큐에 넣지 않는다.
- 계정별 DRAFT 목록은 서버 ACK 이후에도 capture journal의 file spec을 결합한다. 다른 기기의 metadata-only DRAFT에 로컬 파일 보존을 허위 표시하지 않는다.
- 현재 모델의 별도 검토: 원본 완료 조건·실제 diff·queue 계약·account lease·해시 검증·rollback·편집 보존·위젯 dispose 이후 저장 차단을 대조. Worker/Reviewer 사용 없음.

## 로컬 검사
- 영향 검사 11개 PASS: reopen/idempotency, 실제 dispatcher ACK 뒤 file spec 유지, SAVED 편집 보존, 계정·checksum·stale lease 차단, 큐 실패 transaction rollback, single-flight/실패 재시도 및 기존 recorder 화면 회귀.
- 전체 flutter test --no-pub --reporter expanded: 919 PASS, 1분33초. 실제 녹음 bytes 대신 합성 bytes를 사용하는 DB 검사는 실제 AAC 재생 실기를 대신하지 않는다.
- flutter analyze --no-pub: 최종 0 issues, 4.9초. import/중괄호 표기 수정은 동작 변경 없음.
- 실패 기록: ACK fixture가 미지원 user_id 응답 필드를 넣은 문제를 실제 응답 계약에 맞춰 수정; async callback 완료 후 UI frame pump 보완. 전체 검사에서 unrelated interface promotion 미지원 컴파일 오류 1회 확인 후 guarded cast 수정. 반복 수정 실패와 서로 다른 원인을 합산하지 않음. 검사/계정 보호 규칙을 약화하지 않음.
- raw 로그는 Git 제외 .local/workflow/p18-02/에 보존.

## 설치본·최종 CI
- USER-077 회신 후 잠금 해제 실제 확인. APK 39.1초 PASS, install-r Success. 실제 SM_A546S의 기존 P18-01 녹음을 보존해 입력 대기 1개·새 녹음 시작 활성 확인. 검증 앱만 force-stop/restart 후 완료 녹음·입력 대기 1개 재확인. 실제 기기 DB metadata/file/journal 각 1개, 전송 큐 1개, 파일 INPUT_PENDING·journal COMMITTED, 로컬 음성 파일 SHA256 일치 확인. 원본 음성은 출력하지 않음. 새 발화/6분 검사를 요구하지 않음.
- 푸시 직전 실제 원격 main=171e6bf490a32943f05207e95d9dcb8a5e112b57. 커밋/푸시·최종 SHA 필수 Flutter CI는 대기이며 아직 전체 완료가 아니다.
- 다음 P18-03은 최종 완료·원수 finish 후 begin한다.
