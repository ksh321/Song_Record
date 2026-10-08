# P10-10 두 기기 정보 흐름 — 서버 계약과 두 로컬 저장소 통합

## 범위와 근거

원본 plan.txt p00602~604: 오프라인 녹음·티어·같은 메모 수정·동일 TJ 동시 등록·계정 전환. R002/R036/R038/R039/R118 및 V06/V25/V33/X07의 자동 검증 범위를 다룬다. V22의 오래된 기기·영구 삭제와 V28의 공급자 계정 연결 경쟁, 실제 녹음/청취/UI 조작 전체를 이번 검사로 완료 선언하지 않는다. 기존 사용자 검증 범위는 유지한다.

선행 근거: P10 초기/증분 수신은 실제 코드와 기존 필수 CI 통과 기록(8d40ecc 등)에 존재한다. 작업 선택기의 p10.receiver 사실 누락은 기능 미구현 근거가 아니므로 이 근거로 바로잡는다. P10-02 곡·태그·녹음 후속 연결 02268882dd57afa60b510f760ec40a032e2a2928은 필수 CI4 PASS(36838603955/36838603995/36838604019/36838603865). 새 변경은 별도 SHA CI를 확인한다.

## 구현과 발견한 결함

- `TwoDeviceInformationFlowTests.java`: 격리 H2에서 같은 계정의 서로 다른 두 실제 SessionService 세션을 발급한다. 실제 MockMvc 쓰기와 ChangeQueries/ChangeReadView 수신을 연결해 DRAFT→SAVED→티어, 같은 메모 409→명시 revision 수정, 동시 TJ 등록 201/200 canonical 일치, 다른 계정/로그아웃 세션 격리를 검증한다. OAuth 공급자 실로그인·운영 DB·실물 폰을 사용한 테스트는 아니다.
- `fixtures/contracts/two-device-recording.json`: 서버 테스트에서 추출한 요청/응답과 변경 페이지를 Java와 Dart가 함께 사용한다. 합성 계정/기기/녹음 UUID와 비교용 updated_at만 고정했으며 토큰·Authorization·개인 데이터는 포함하지 않았다. Java 테스트가 매번 현재 응답과 이 파일을 비교한다. 숫자 표기는 JsonNode 재직렬화될 수 있고 숫자 값·구조가 계약 근거다.
- `two_device_information_flow_test.dart`: 별도 디렉터리의 두 AccountStore와 실제 Repository/dispatcher/초기 기준 사본/ChangeFeedReceiver를 사용한다. A의 오프라인 생성→저장, B의 재시작 후 수신→티어 수정, A의 증분 수신을 확인한다. A 합성 파일의 바이트 보존과 B 파일 부재를 검사한다. 전송은 위 서버 계약의 재생이며 실행 중 Java 서버와 직접 통신하는 단일 E2E 또는 유효 음성 파일 검사라고 주장하지 않는다.
- 실제 계약 교차 검증으로 정수 응답 표기 결함을 발견했다. 서버 CanonicalRequest는 540을 5.4E+2처럼 직렬화할 수 있는데 일반 jsonDecode는 double로 읽어 기존 앱의 정수 검사가 정상 응답을 거절했다.
- `wire_json.dart`: 응답 JSON이 원래 유효한지 먼저 검사하고 문자열 밖 숫자 토큰의 정확한 십진 값만 분석한다. 수학적으로 정수이며 signed 64-bit 범위일 때만 정수 표기로 읽는다. 반올림/소수 절삭/지수에 따른 대량 할당을 하지 않는다. 1.0000000000000001·범위 초과·잘못된 JSON은 정수로 인정하지 않는다.
- 송신 ACK/충돌 current, 증분 payload, 초기 사본 payload에 연결했다. 기존 outgoing body/op_id/hash/서버 멱등 원장은 변경하지 않았다. change feed 외부 cursor/revision 타입 검사는 그대로 유지한다. 스냅샷 canonical_payload 문자열과 manifest 해시 입력 바이트도 보존한다.

## 실제 검증과 검토

- `gradlew.bat test --offline --no-daemon --tests '*TwoDeviceInformationFlowTests'`: **4 PASS / 실패·오류·skip 0**, 실제 XML 확인. Java21 및 기존 로컬 Unix-domain socket 경로 우회 사용. 로그 p10-10-two-device-server-final.log. 첫 실행은 재사용 fixture에 이미 있는 파일 명세 테이블을 중복 생성해 setup 실패했고 중복 DDL만 제거했다.
- `flutter test --no-pub test/wire_json_test.dart test/two_device_information_flow_test.dart test/metadata_response_test.dart test/metadata_dispatcher_test.dart test/change_feed_response_test.dart test/change_feed_store_test.dart test/change_feed_receiver_test.dart test/snapshot_receiver_test.dart test/resync_integration_test.dart --reporter expanded`: **180 PASS**, p10-10-numeric-integration.log.
- `flutter test --no-pub test/snapshot_response_test.dart test/snapshot_download_store_test.dart test/snapshot_recording_baseline_test.dart --reporter expanded`: **27 PASS**, p10-10-snapshot-numeric.log. 원문 해시·초기 저장·기준 사본 영향을 검사했다.
- 변경9개 Dart 파일 analyze의 중괄호 지적1개를 보완했고 해당 파일 재분석 No issues found. 앞서 새 Object? 반환형 연결에서 스냅샷의 명시 Map 변환이 빠진 컴파일 오류1회를 고쳤다. 테스트 삭제/약화 없음. 기존 증분 envelope의 2.0 거절 검사도 유지·통과했다.
- 현재 모델이 문자열 escape, 정수 경계/반올림, 과대 지수, 원본 요청/해시 보존, 계정별 DB와 세션 fencing을 직접 검토했다. 별도 에이전트 검수 아님. 현재 모델/속도의 실행 설정 변경은 확인하지 않았으며 변경했다고 보고하지 않는다.

## 남은 범위와 재개

이 묶음의 커밋·정확 SHA CI 후 P10 전체 요구사항/기존 실기 근거를 대조한다. V22 삭제·재동기화 결합과 새 변경에 꼭 필요한 실제 폰 동작을 자동 검증과 구분한다. 이미 확인한 기존 실기를 문서 부족 때문에 반복 요청하지 않는다. 사용자 직접 조작 요청은 현재 없음.

## V22 삭제·만료 커서 결합 — 2026-10-01

- 원본 P10-08/09 완료 기준과 R041/R042/V22 중 자동 검증 가능 범위. `resync_integration_test.dart`의 기존 정상 사본 교체 검사를 유지하고 삭제 원장 포함 분기를 추가했다.
- CURSOR_EXPIRED → 19개 엔티티 사본 다운로드·해시 검증·교체 → 증분 수신 → 송신 게이트 재개를 실제 저장소/수신기로 연결한다. 새 사본에서 SONG을 제거하고 별도 원장 UUID의 entity_id로 영구 삭제를 투영한다.
- 기존 오프라인 입력·모든 요청/큐 테이블·합성 파일 바이트를 보존한다. 재시작 후 더 높은 revision의 부활 응답도 거절하며 모든 저장 테이블과 커서가 불변인지 검사한다. sender는 실행 시점 확인용 대역이므로 이 검사만으로 실제 네트워크 송신 완료 또는 실기 완료라고 하지 않는다.
- `flutter test --no-pub test/resync_integration_test.dart test/deleted_song_recording_test.dart test/permanent_deletion_test.dart --reporter expanded`: 6 PASS. 로그 `.local/workflow/p10-10-deletion-resync-final.log`. 삭제된 곡 참조 녹음의 미연결 ACK·원래 요청·파일 보존 기존 검사도 함께 통과했다.
- 테스트 작성 중 ordinal=0 계약 자료 오류를 1로 수정했다. 재시작 후 복구 내보내기 전체 문자열 비교는 매 호출 생성 시각 때문에 실패하여 생성 시각이 아닌 모든 실제 tables를 비교하도록 수정했다. 제품 오류를 숨기거나 검사 범위를 축소한 변경이 아니다. 명령 실행 폴더 착오로 로그 경로를 찾지 못한 1회는 테스트 미실행으로 구분한다.
- 현재 모델 직접 검토: 기존 정상 분기 유지, 원장/대상 UUID 구분, 해시 재계산, queue 원문 보존, 재시작 후 원자적 거절, 실제 사용자 데이터 미접근 확인. 별도 에이전트 검수 아님.
- ae8093d860295caeb970cd7727ae4dbc307ee197의 API contract/Idempotency MySQL/Development workflow PASS, CI run36841099551 진행 중. 새 테스트의 대상 커밋은 커밋 후 Git 이력으로 식별한다.

- 최종 `dart analyze test/resync_integration_test.dart`: No issues found. 빈 List의 명시 타입 경고1개 보완. 테스트6 PASS는 중복 실행 횟수를 합산하지 않은 최종 결과다.

## 충돌 화면·실제 저장소 결합 및 통합 결과

- `conflict_screen_integration_test.dart`: 실제 ConflictScreen→LocalRepository→계정 SQLite를 연결해 로컬 선택/서버 선택/선택 도중 계정 전환 3사례를 추가했다. 화면 선택 후 DB를 닫고 다시 열어 새 요청·선택값·원본 요청/기준/서버 응답/시도 횟수 보존을 확인한다. 계정 전환은 저장 실패 안내와 양쪽 계정 격리를 함께 검사한다.
- 초기 테스트 하네스는 가상 시계에서 실제 SQLite 완료 신호를 기다려 timeout(1차), runAsync 중첩 금지(2차), 완료 신호가 가상 구역에 남아 timeout(3차)이 발생했다. 제품 논리 변경 실패가 아닌 테스트 실행 환경 문제로 구분했다. 로컬 Flutter binding의 runAsync 구현을 확인한 뒤 DB 호출과 완료 신호를 동일 실제 이벤트 구역에서 실행해 해결했다. 모델 상향/실제 폰 검증으로 주장하지 않는다.
- 서버 값 선택 후 local_payload를 null로 예상한 새 테스트의 가정도 기존 계약/기존 테스트와 대조해 수정했다. 실제 계약은 선택한 서버 사본을 로컬 표시값으로 유지하며 새 요청은 만들지 않는다. 제품 정책 변경 없음.
- 최종 명령: `flutter test --no-pub test/conflict_screen_integration_test.dart test/conflict_screen_test.dart test/conflict_resolution_store_test.dart test/resync_integration_test.dart test/deleted_song_recording_test.dart test/permanent_deletion_test.dart --reporter expanded`: **29 PASS**, 로그 `.local/workflow/p10-10-final-integration.log`. 앞선6 PASS와 중복되어 합산하지 않는다.
- `dart analyze test/conflict_screen_integration_test.dart test/resync_integration_test.dart`: **No issues found**. 현재 모델은 UI 실선택→실제 저장→재시작/계정 전환 경계와 실패 시 원본 보존을 직접 검토했다. 테스트만 변경했고 실사용 DB/앱을 수정하지 않았다.
- 앞선 제품 ae8093d860295caeb970cd7727ae4dbc307ee197 **필수 CI4 PASS**: CI36841099551 / API36841099417 / MySQL36841099414 / Development36841099495. 앞의 진행 중 문구는 당시 관측이다.
- 다음: 현재 테스트 묶음의 정확 SHA CI 확인, P10-03b-FIXTURE의 실제 기기에서 비어 있지 않은 큐/충돌 화면 확인을 위한 안전한 준비. 기존 USER-024/025를 재요청하지 않고 새 변경 범위만 구분한다. 실제 두 기기·녹음/청취 확인은 자동 테스트29개로 완료 판정하지 않는다.

## 다른 기기 변경 수신 후 오프라인 수정 연결 — P10-02/P10-07/P10-10

- 실제 수신→전송 순서를 대조해 결함을 재현했다. 원래 기준1로 저장한 오프라인 메모가 다른 기기의 revision2를 먼저 수신하면 planner가 영구 보류하여 서버409/선택 화면으로 넘어가지 않았다. `received_revision_conflict_test.dart`에서 초기19종 사본→로컬 메모 저장→증분2 수신→DB 재시작→전송을 연결했을 때 기대1회/실제0회였다.
- `dependency_planner.dart`는 알려진 서버보다 오래된 양수 기준의 요청을 원문 그대로 보내 서버의 권위 있는409/current 응답을 받게 한다. 기준0/없는 기준/알려진 서버보다 앞선 기준/삭제 대상/선행 의존/매핑 보류 검사는 유지한다. revision을 최신값으로 자동 바꾸거나 가짜409를 저장하지 않는다.
- 첫 확대 검사에서 사용자 충돌 선택 뒤 쌓인 더 최신 초안의 기존 보류 조건1개가 실패했다. `conflict_eligibility.dart`의 검증된 해결 이력으로 같은 대상·뒤쪽 순서·미전송 PATCH·이전 기준 초안을 명시 보류해 원본/최신 입력을 유지했다. 기존 테스트는 변경/삭제하지 않았다. 해당 보류 초안의 후속 사용자 검토 경로는 아직 전체 P10-07 완료 근거로 확대하지 않는다.
- 테스트는 원래 op_id/body/base_payload 보존, 실제 형식409 수신, 양쪽 메모 선택 후보, 명시 로컬 선택→새 op_id/기준2→ACK3까지 확인한다. 전송은 합성 서버 응답이며 물리 두 기기 검증이 아니다.
- `flutter test --no-pub test/received_revision_conflict_test.dart test/dependency_planner_test.dart test/metadata_conflict_test.dart test/conflict_resolution_store_test.dart test/metadata_followup_dispatch_test.dart test/recording_followup_conflict_test.dart --reporter expanded`: **47 PASS**. 로그 p10-07-received-conflict-final.log.
- `flutter test --no-pub test/metadata_dispatcher_test.dart test/mutation_retry_test.dart test/canonical_song_store_test.dart test/conflict_resolution_plan_test.dart test/recording_tier_dispatch_test.dart test/recording_link_dispatch_test.dart --reporter expanded`: **103 PASS**. 로그 p10-07-received-conflict-regression.log.
- 변경3파일 dart analyze **No issues found**. 최초 테스트 타입 import 누락1회는 컴파일 단계에서 수정했다. 문제 ID P10-RECEIVED-REVISION: 재현 후1차 수정이 기존 보존 검사1개 실패, 보완2차 통과. 현재 모델 직접 요청 불변/계정 경계/후속 순서/실제 diff 검토. 모델 변경 주장 없음.
- USER-028은 7e86f7c의 새 충돌 UI/인증 차단 복귀①~④ 사용자 정상 확인 완료다. 이 새 planner 변경의 근거는 위 자동 검증으로 별도 기록하며 사용자 확인을 소급 확대하지 않는다. 같은 UI 실기를 반복 요청하지 않는다.

## 최종 대조에서 확인된 현재 잔여 범위

- V28 이메일 자동 병합 금지/공급자 ID 경쟁은 기존 P06 사용자 확인 범위다. IdentityLinkTests.sameEmailDoesNotMergeAccounts, concurrentConsumptionHasExactlyOneWinner, twoUsersCannotClaimSameNewIdentity 실제 구현도 확인했다. 새 인증 기능 변경이 없어 문서 부족으로 재검증 대기시키지 않는다.
- P10-02 목록/파일 송신 어댑터와 녹음 작성 UI는 원본 P19/P12/P18 경계이며 P10에 역선행으로 붙이지 않는다. 기존 planner/보존 검증은 유지한다.
- 새로 확인해야 할 구체적인 잔여 사항: 사용자 해결 뒤의 더 최신 보류 초안 검토 경로, canonical 매핑의 개인 편집 보류를 사용자 선택으로 이어주는 경로, V25/V33의 전체 클라이언트 연결. 기존 a~h 완료 이력을 지우거나 같은 기능을 다시 구현하지 않고 실제 미연결 지점만 처리한다.


## 2026-10-08 P10-10-NEXT 원수 방식 — 진행 중

- 승인: P10-09와 같은 현재 대화 직접 수행, 종료 범위 P10-10. 별도 실행기 AI·하위 에이전트·사용량 조회 없음. 사용자 장비는 노트북과 폰 1대이므로 Android 에뮬레이터를 두 번째 실행 환경으로 사용한다.
- 시작 HEAD와 새 원격 조회 main: c1a36f600ec3b08881856827fbe0e7d9cd694e75. 기존 미커밋 사용량/워크플로우 및 P10-08/09 기록은 보존한다.
- 기존 최신 보류 초안/개인 편집 선택 경로는 P10-07 완료 근거로 해소됐다. 기존 V28/P06 사용자 확인을 되돌리지 않는다. 이번 잔여는 두 Android 실행 환경의 실제 HTTP 정보 교환 및 V25/V33 선택 연결이다.
- `two_device_information_flow_test.dart`: 미전송 입력을 가진 계정 전환에서 다른 계정의 메타데이터/큐/커서/파일 부재, 이전 lease 및 다른 계정 인증 송신 거절, 원계정 복귀 후 요청·파일·복구 테이블 보존을 추가했다.
- `DeviceFlowHarnessTests.java`: opt-in loopback HTTP 서버를 기존 실제 세션/쓰기 컨트롤러/변경 수신/H2 fixture에 연결한다. 운영 서버·실계정·사용자 DB에 접근하지 않는다. 일반 테스트에서는 서버 세션 경계 검사를 수행하며 장시간 실기 서버는 환경 변수로 명시 실행할 때만 시작한다.
- `tool/two_device_verification.dart`와 검증 홈: 폰 A/에뮬레이터 B가 실제 HttpMutationTransport/HttpChangeFeedTransport, 계정별 SQLite, 충돌 화면을 사용한다. 합성 4바이트 파일 보존 확인이며 유효 음성 재생·실제 오프라인 녹음의 신규 통과 근거로 확대하지 않는다. 과거 해당 기능 실기는 보존한다.
- 자동 검사: Flutter 관련 11파일 **93 PASS**; Java TwoDeviceInformationFlow/IdentityLink/RecordingDraft/DeviceFlowHarness **40 PASS, 실기 서버 opt-in 1 skip**. skip은 통과에 포함하지 않는다. Flutter lib/관련 테스트/tool 분석 PASS, verification debug APK 빌드 PASS, 원본 색인·diff 검사 PASS. OpenAPI/로컬 참조/security/7 wire examples/141 schema boundary cases PASS.
- 계약 검사에 기본 Python 3.10이 고정 rpds-py 의존성을 설치할 수 없어 별도 로컬 Python 3.12 가상환경으로 실행했다. 핀·검사·제품 코드를 약화하지 않았다. Dart 형식 경고는 중괄호로 수정했고 분석을 재통과했다.
- 실제 기기 자동 조작 관측: 폰 A DRAFT→SAVED가 에뮬레이터 B revision2로 수신됨. B의 티어 A가 폰 A revision3으로 수신됨. 양쪽 대기0, A 파일 SHA 보존=true, B 파일 없음. 이후 동시 기준 메모의 B 송신 후 A 송신은 실제 충돌로 이어져 화면에 서버 B 새 메모 / 기기 A 새 메모 표시. 이는 AI 관측이며 사용자 선택 통과는 아직 아니다.
- 재개 보완: 같은 서버 계정/기기/녹음 식별값의 격리 실행을 다시 연결하면 기존 SQLite를 열어 충돌·입력을 보존한다. 초기 테스트 실행의 공개 식별값만 기존 검증 디렉터리에 보충했다. 인증 토큰은 메모리에만 유지한다.
- 현재 모델 직접 검토: test/debug 전용 진입점, localhost 바인딩, 기존 인증 검사, 원본 큐/파일 보존, 타 계정 송신 차단을 대조했다. 별도 모델·독립 에이전트 검수로 주장하지 않는다. 사용자 충돌·동일 곡 선택, 선택 후 양쪽 최종 수신, 커밋·정확 SHA CI가 남았다.
- 원시 로그/결과는 Git 제외 `.local/workflow/p10-10-manual/`에 저장. 실기 서버 PID26984, 에뮬레이터 emulator-5556. 서버는 45분 제한이며 수신 대기 AI 호출은 없다. 제품 실행기 checkpoint는 과거 P10-08 완료 상태로 유지한다.

- USER-040 판본1: 최종 설치 APK 7dcb00c24db3e4b433e7ec7a6ef9b768d6e750df3f643bc78cca0903a258b11a에서 개인 메모 B/A 및 녹음 메모 B/A를 실제 확인해 2개 선택을 요청. 재설치 후 기존 충돌 재개 성공. 실기 서버의 곡 ID 후속 경로 허용을 검토 중 추가했으며 현재 서버는 추가 전 클래스로 실행 중이다. 이번 서버 값 선택에는 새 경로가 사용되지 않는다. 서버 종료 후 최종 소스 회귀 검사는 남은 AI 단계로 명시한다.


### USER-040 완료 및 최종 로컬 검토

- 사용자 “2번까지 정상” 회신: 설치본 판본1의 ① 동일 TJ 개인 편집 서버 값 선택, ② 녹음 메모 이 기기 입력 선택 모두 정상. 후속 실제 HTTP 송신과 두 기기 증분 수신에서 RECORDING revision5 / A 새 메모 / tier A / 대기0을 확인했다.
- 양쪽 격리 SQLite의 서버 녹음 payload와 canonical SONG payload가 동일함을 직접 비교했다. TJ990001은 동일 canonical UUID와 B 개인 메모로 수렴했고 A의 원래 개인 메모는 RESOLVED intent의 후보/원본에 보존됐다. A 파일 SHA 보존=true, B 파일 없음. 파일 업로드 없이 메타데이터만 교환했다.
- 검증 화면을 벗어난 뒤 같은 데이터 재개·앱 데이터 보존 업데이트도 확인했다. 실기 서버 정상 종료(BUILD SUCCESSFUL), 이번 작업에서 만든 에뮬레이터 종료 및 폰의 검증 포트 연결 제거 완료. 실제 앱 데이터 삭제 없음.
- 후속 곡 PATCH 라우팅은 `bridgeRoutesSongCreationAndPersonalEditThroughRealControllers`로 실제 HTTP 생성→개인 메모 PATCH200과 결과를 검증했다. 최종 서버 회귀 **41 PASS / opt-in 서버 1 skip / 실패0**. 앞서40 PASS에 단순 합산하지 않는다. 로그 server-final.log.
- 최종 현재 모델 검토: 원본 V06/V22/V25/V28/V33와 기존 완료 근거를 대조했다. 이번 변경은 계정 전환 회귀와 debug/test 연결이며 제품 정책·실데이터를 변경하지 않는다. 기존 인증·삭제·재동기화·최신 초안/개인 편집 선택 완료 근거를 유지한다. 새 실기와 기존 자동/사용자 근거를 합쳐 P10-10 잔여를 충족하며 최종 정확 SHA CI 통과 전 완료로 선언하지 않는다.
- 검토 지적 해결: 검증 홈의 서버 미통신 안내를 실제 동작에 맞게 수정, 검증 화면 재진입 데이터 보존 추가, 곡 ID 후속 경로 누락 보완 및 실제 HTTP 회귀 통과. 현재 요청·관측 모델 설정을 바꾸지 않았으며 별도 AI 호출 없음.
- 다음: 이 변경 커밋·푸시 후 ci-policy가 요구하는 Flutter/서버/MySQL 및 idempotency CI 대조. 승인 범위 종료 P10-10.
