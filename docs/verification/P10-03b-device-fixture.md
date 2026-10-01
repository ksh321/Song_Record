# P10-03b-FIXTURE — 분리된 동기화 실기 준비

## 목적과 보존 경계

기존 USER-024/025는 기존 초기/증분 수신 UI 확인으로 유지한다. 새 비어 있지 않은 큐·충돌 선택·인증 실패 복귀를 실제 휴대폰에서 확인할 자료가 없어, P10-03b-FIXTURE의 기존 등록 범위로 검증 앱을 추가했다. 기존 사용자 기능을 미검증으로 되돌리는 작업이 아니다.

- Android `verification` flavor: `com.ksh321.songrecord.verification`, 표시명 ‘노래기록 동기화 검증’. 기존 DEV 패키지와 다른 앱이다. 기존 앱 삭제/데이터 초기화/서명 교체 없음.
- `tool/sync_verification.dart`는 debug+verification에서만 시작한다. 제품 main.dart는 변경하지 않았다. 검증 앱만 합성 고정 계정과 새 실행 디렉터리를 사용한다. 이전 실행도 삭제하지 않는다.
- `tool/sync_verification_fixture.dart`는 실제 AccountStore/LocalRepository/RepositorySyncBackend/SyncController를 사용하고 전송만 합성 응답이다. HTTP·OAuth·사용자 토큰·녹음·업로드를 하지 않는다. 실제 네트워크/두 물리 기기/녹음 청취 완료 근거로 확대하지 않는다.
- 충돌 선택, 8초 지연401, 8초 지연403을 각각 새 자료로 실행한다. 폰에는 실제 SyncScreen/ConflictScreen을 표시하고 controller에 Android lifecycle을 전달한다. 자동 시작하지 않고 사용자의 ‘검증 시작’을 기다린다.
- 재현 명령: `flutter build apk --debug --flavor verification --target tool/sync_verification.dart --no-pub`. Java21와 기존 로컬 Unix-domain socket 경로 사용. 로그인 설정 파일 불필요.

## 새로 발견한 인증 차단 경계

P10-AUTH-LATE-RESUME: 401/403 응답이 끝난 뒤의 뒤늦은 foreground 복귀에서 자동 전송이 재개되어 두 번째 항목이 보내졌다. 기존 ‘첫 요청 진행 중 복귀’와 다른 경계다. 새로운 재현2사례에서 기대1회/실제2회 실패를 확인했다. 과거 실패 기록을 지우지 않으며 새 경계 재현1회·보완1회로 기록한다.

`SyncController._run`의 모든 자동 진입에서 backend.automaticFollowupAllowed를 확인하도록 보완했다. 진행 중 후속 실행 검사만으로는 늦은 복귀/예약 타이머 진입을 막지 못했다. 명시적 사용자 복구와 자동 실행을 구분하는 기존 resetFailures 경로는 유지한다. 데이터/큐/인증 정보를 수정하지 않는다.

## 실제 검증

- 새 fixture3 PASS 후, 실제 transport 진입 신호를 기다린 다음 이탈·복귀·응답을 결합하도록 검사 강화. sleep으로 시점을 추정하지 않는다.
- `flutter test --no-pub test/sync_verification_fixture_test.dart test/sync_controller_test.dart test/snapshot_sync_backend_test.dart test/change_feed_sync_backend_test.dart test/mutation_retry_test.dart --reporter expanded`: **73 PASS**, `.local/workflow/p10-03b-fixture-auth-final.log`.
- 401/403 전송 중 복귀와 응답 후 늦은 복귀 모두 전송1회·시도[1,0]. 다른 실행 디렉터리/무관한 파일 보존, 실제 충돌 선택 후 ACK도 확인했다.
- 변경 controller/검증 entrypoint/fixture/test 분석 **No issues found**. 현재 모델이 실제 diff·계정별 경로·자동/명시 실행·합성 전송/로그를 직접 검토했다. 별도 에이전트 검수 아님.
- 인증 차단 보완 뒤 최종 APK 빌드 성공(12.1초). aapt로 package=com.ksh321.songrecord.verification, version=1.0.0+1, 표시명 노래기록 동기화 검증을 확인했다. SHA256=DCB4D478FB46B423D7FEC20926A52C2FA9A25947F4328853DBE3FCCA7E1C6511. 서버/사용자 DB 변경 없음.

## 실제 기기 준비와 다음 단계

USB 승인 기기0대 확인. USER-027은 연결 요청만이며 ntfy 서버가 접수했다. 휴대폰 수신/연결/실기 완료는 미확인이다. 연결 후 정확 APK 패키지·해시를 확인하고 별도 앱 설치→기동/로그 자동 확인을 먼저 수행한다. 이후 사용자에게 최신 대상과 충돌 선택/401/403 복귀 순서를 명시해 요청한다. 현재 사용자의 테스트 요청은 아직 없다.

제품 전체 P10 완료 아님. 새 UI 물리 기기 조작은 대기이며 자동 테스트를 대체 근거로 부풀리지 않는다.

## 설치·커밋 관측

7e86f7caf4ce4c9d124810dc1665ce8b22b41bda 일반 푸시 완료. USB 연결 회신 후 승인1대/별도 앱 설치·기동 성공/설치 APK 해시 일치/해당 앱 오류4종0 확인. USER-027 완료, 새 실기는 USER-028로 요청. CI는 별도 확인 중. 직전71c09207f602a966ffcfa0d6f5fed919a4f253c6 필수 CI4 PASS(36843146048/36843146067/36843145856/36843145985).

USER-028 사용자 ‘1~4까지 다 정상’ 확인 수신. 지정 합성 검증 앱에서 충돌 선택2종과 지연401/403 복귀 범위 실기 확인 완료. 실제 OAuth/녹음/두 물리 기기 완료로 확대하지 않는다. 새 코드 CI 확인은 별도 유지한다.

최종 CI: 7e86f7caf4ce4c9d124810dc1665ce8b22b41bda 필수4 PASS(CI36844611594/API36844611588/MySQL36844611644/Development36844611715). USER-028①~④ 정상 확인과 합쳐 이 새 실기 준비/인증 차단 범위 완료. 전체 P10은 별도 잔여 연결을 유지한다.
