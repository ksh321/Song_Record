# P12-05 — 앱 전송 큐 연결

## 범위와 상태

사용자 P12-06까지 원수 승인. P12-04 실제 검사·CI 완료 뒤 측정 begin(P12-04 finish 직후 집계 잠금 경합 1회는 정상 해제 뒤 begin 재실행, 제품 중복 실행 없음).
구현·현재 모델 검토·로컬 검사 완료. 휴대폰 노트북용 검증 APK 설치·실행 완료, USER-046 판본2 확인 대기. 필수 설치본 확인·커밋·푸시·CI는 아직 완료되지 않음. P12-06 미착수.

## 구현

원본 계획 P12-05(XML p00654~656), 설계 5.3/8.3, R050·R068·R073. 상세 `apps/mobile/UPLOAD-QUEUE.md`.

- 계정별 SQLite v10 전송 큐와 v1~9 보존 이관. 초기/재발급 멱등 ID·시도 ID·명세·자동 재시도 예산 보존, URL/인증 토큰 미저장.
- 승인된 서버 ACTIVE/SAVED와 실제 로컬 검증 파일 명세를 대조. 기존 정보 전송 뒤 큐 실행, 고정/교체 우선. 타 계정/취소된 claim의 늦은 응답 차단.
- HTTP 승인과 R2 PUT 연결. 앱 Bearer는 API에만, R2 HTTPS 호스트 제한 및 리디렉션 차단. 1·5·15분 최대 3회 자동 재시도, 인증/정책 차단은 무한 재시도하지 않음.
- PUT 성공은 UPLOADED. 검증 전 서버 STORED로 바꾸지 않으며 P12-06 complete 연결을 기다림. 파일과 정보는 삭제하지 않음.
- 별도 합성 검증 앱은 기존 verification flavor 사용. 실제 계정·녹음과 분리된 디렉터리에서 7개 결과를 확인.

## 실제 로컬 검사와 검토

- 최종 일괄 `flutter analyze --no-pub` 경고/오류 0, `flutter test --no-pub --reporter expanded` 808 PASS, dev 검증 대상 APK 빌드 PASS.
- 이후 현재 모델 별도 검토에서 해결된 오프라인 원본 이력이 영구 차단될 수 있는 경계를 발견. 기존 readMappingEligibility를 재사용해 해결 이력과 실제 미완료를 구분. 원본/이력 삭제 없음.
- 보강 후 analyze 경고/오류 0, upload_queue_test + upload_transport_test 4 PASS(7개 보존 시나리오·실제 로컬 HTTP 요청/리디렉션 차단·R2 URL 제한·해결 이력 회귀). 이 보강 뒤 전체 809개 실행으로 확대해 기록하지 않음. 최종 전체 회귀는 필수 CI에서 확인.
- v1~9 이관과 큐 보존 검사 13 PASS. v9의 기존 SQL 객체 변경 0, v10에 큐/인덱스/보호 트리거 3개만 추가.
- 처음 DB 버전 기대값/생성 스냅샷 줄바꿈 실패는 원본 SQL/기대 버전 정정 및 v10 생성물 재생성 후 해결. 실패 검사를 제거/약화하지 않음. 일반 자동 formatter 중괄호/정렬 정보는 수정 후 analyze 통과.
- 검토: 같은 현재 모델, 원수 요청 Astra/medium. 별도 모델/에이전트 호출 없음. 데이터 보존·명세 일치·멱등성·재시도 예산·계정 fence·미완료 이력을 실제 코드/원본/결과로 대조.
- 로그 `.local/workflow/p12-05/` (Git 제외). 실제 사용자 음성/인증값 없이 합성 fixture만 사용.

## 남은 조건

설치본 실제 휴대폰 7개 항목 확인 → 검증한 변경만 커밋·푸시 → 필수 Flutter CI → P12-05 완료 측정 → P12-06 시작. 현재 USB 연결·설치 완료. 잠금 해제 후 설치본 검증 버튼 조작과 7개 결과 확인만 사용자 요청 대상.

학습 개념: 정보 승인과 파일 전송은 별도 단계다. 전송 성공은 서버 검증 완료가 아니며, 재시도해도 로컬 원본과 기존 수정 이력을 유지해야 한다.

## 설치 준비 완료

최종 verification APK 빌드 PASS, SHA256 3b2ab2a4e078775a2f5e36cfdf6ee223b9d147215ac4ee13cb249f8ae1c588ee. 패키지 com.ksh321.songrecord.verification. 생성 코드·v10 스냅샷 재생성 해시 동일, diff 검사 PASS. ADB 장치 없음 재확인, USER-046 USB 연결 요청. 실행 중 제품/빌드/CI 프로세스 없음, 미커밋 변경 보존, P12-06 미착수.

## USB 회신 후 설치 — USER-046 판본2

USB 승인 장치 확인. 기본 verification 패키지는 INSTALL_FAILED_UPDATE_INCOMPATIBLE으로 업데이트 거절. 기존 P10-07 근거와 설치 패키지를 대조하여 이미 사용 중인 verification.laptop 대상에 빌드했다. 패키지/표시명만 일시 변경하고 Gradle 원본 바이트 복원·Git diff 없음 확인. 앱 삭제·데이터 초기화 없음.

- 최종 노트북 APK SHA256: d40e0cdd94a44be86c847439a27043abaed1990a7bab31a27ce102ecf8cb6ccc
- adb install -r: Success. com.ksh321.songrecord.verification.laptop / MainActivity 실행·프로세스 확인.
- 기기는 잠금 표시 showing=true, UI 패키지는 systemui. 실제 검증 화면 표시/7항목 통과를 추정하지 않음.
- USER-046 USB 연결 요청은 해결. 판본2 잠금 해제·검증 시작·7개 결과 회신 대기. 미커밋 보존, 빌드/설치 종료, 검증 앱 실행 중. P12-06 미착수.

## 설치본 사용자 확인 완료

USER-046 판본2의 7개 항목에 사용자 “통과” 회신. 노트북용 APK 설치 근거와 대조하여 합성 설치본 실기 통과로 기록한다. 실제 R2 전체 업로드 완료·서버 STORED 검증으로 확대하지 않는다. 현재 모델 검토 승인 유지, 남은 단계 커밋·푸시·필수 Flutter CI.

### P12-05 완료
- 8ecc594858b1ec28a0083df8f9600e7a5def88de, 기준 f0676a5. CI 37761858828 필수 Flutter 생성물·분석·테스트·Android 빌드 PASS. 설치본 7개 사용자 확인 및 현재 모델 검토 대조 완료. 다음 P12-06. CI 폰 알림 서버 접수, 실제 수신은 미확인.
