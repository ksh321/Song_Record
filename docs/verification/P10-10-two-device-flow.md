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
