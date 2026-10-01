# P10-06c — 증분 변경 수신: 앱 응답 검증기

2026-10-01. 원본 P10-06 p00590~592 및 R040의 앱 수신 연결을 위한 세부 작업이다. 선행 P10-06b HTTP 계약과 공유 사례를 사용한다. 순수 응답 검증 범위이며 네트워크 호출·DB 반영·커서 전진은 아직 연결하지 않았다.

change_feed_response.dart는 기대한 시작 순번, 연속 순번, next/head/has_more/limit 일관성, canonical UUID, 양의 revision, 정수 상한, 정확한 필드, 계정·payload 식별자 일치를 검사한다. 서버 CONDITION은 LocalEntity.recordingCondition에 명시 매핑한다. DELETE는 의미를 재해석하거나 파일을 지우지 않고 보존한다. 페이지 owner를 유지하고 entries 변경을 금지하며 payload는 별도 사본으로 반환한다. 출력 문자열에 원문 데이터를 노출하지 않는다.

검증 명령:
- dart format lib/core/sync/change_feed_response.dart test/change_feed_response_test.dart
- flutter test --no-pub test/change_feed_response_test.dart --reporter expanded: 8 PASS.
- flutter analyze --no-pub lib/core/sync/change_feed_response.dart test/change_feed_response_test.dart: No issues found.

공유 OpenAPI 사례7개, Long 최대값, 빈 완료 응답, 순번 틈·중복·커서 점프, 잘못된 more, 소유자/ID/revision 불일치, 숫자 강제 변환 거절, 삭제 보존·불변 사본을 확인했다. 최초 테스트 fixture의 Map 타입 추론 오류를 명시 dynamic Map으로 수정했다. 테스트를 삭제하거나 약화하지 않았다. 최종 로그는 .local/workflow/p10-06c-decoder-final.log. 현재 모델 별도 코드 검토에서 전체 응답 검증 전 부분 반영이 없고 성공 디코딩을 DB 적용 완료로 취급하지 않음을 대조했다. 모델/속도 변경을 주장하지 않으며 외부 위임 없음.

다음: 인증된 HTTP transport, 계정 저장소 트랜잭션과 성공 커서의 원자 적용을 실제 계약에 맞게 연결한다. 스냅샷의 관계 타입과 metadata_copies를 무조건 합치지 않으며 기존 초안·base_payload·파일을 보존해야 한다. 전체 P10-06 완료 아님. 이 순수 검증기는 현재 폰에 설치한 e4adb7f에 포함되지 않는다. 대상 SHA CI는 후속 통합 커밋에서 확인한다.
