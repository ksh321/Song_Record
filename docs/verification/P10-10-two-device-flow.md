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
