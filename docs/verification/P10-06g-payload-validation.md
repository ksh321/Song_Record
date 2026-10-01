# P10-06g — 증분 변경 수신: 업무 payload 검증

2026-10-01. 원본 P10-06 p00591~592와 기존 OpenAPI Song/RecordingDraft/RecordingSaved/RecordingEdited/Tag 및 실제 변경 로그 생산 코드를 대조한 후속 세부 ID다.

change_payload_validation.dart를 ChangeFeedStore의 UPSERT 쓰기 앞에 연결했다. 현재 실제 서버 작성 경로인 SONG/RECORDING/TAG의 필수 필드·허용 필드·타입·범위·UUID·UTC 달력 날짜·열거형을 검사한다. 곡 번호 문자열의 선행0을 보존하고 key mode/shift 짝, 태그 UUID 집합과 이름 사본, 확정 파일 명세7필드/용량/형식을 검사한다. 값은 정규화해 바꾸지 않는다. 과거 컨디션 UUID 및 Draft/Saved 응답의 컨디션 생략을 읽기 호환으로 허용하며, 그 경우 이전에 아는 컨디션 코드·이름을 보존한다. 명시 null은 별도 값이다.

완성된 전용 wire 계약이 없는 PLAYLIST/CONDITION UPSERT도 현 단계에서는 적용 전에 거절한다. 이는 서버 기능을 지우거나 원본 계획을 변경한 것이 아니라, e 저장 기반의 넓은 엔터티 허용을 실제 생산 경로로 좁혀 부분/잘못된 payload의 커서 통과를 막는 조치다. DELETE 계약/원장 투영 및 관계/asset은 후속 범위다. 실제 앱 자동 수신 연결 전이며 설치된 e4adb7f에 포함되지 않는다.

검증:
- flutter test --no-pub test/change_payload_validation_test.dart test/change_feed_store_test.dart test/snapshot_download_store_test.dart test/recording_change_projection_test.dart test/change_feed_response_test.dart test/change_feed_transport_test.dart --reporter expanded: **50 PASS**.
- 관련7파일 flutter analyze --no-pub: **No issues found**.
- 실제 공유 계약의 RecordingDraft/Saved/Edited 사례를 읽어 검증했다. 원자 적용 테스트 자료도 실제 필드를 가진 사본으로 강화했고 부분 payload 실패·전체 롤백 검사를 유지했다. source 번호 타입, 잘못된 달력 날짜, enum, 누락/예상 밖 필드, 중복/불일치 태그, 파일 용량·형식 오류를 거절한다.

최초 분석에서 dynamic 숫자 비교/문자열 전달 타입 오류와 중괄호 권고가 나와 Object? 지역 변수의 타입 검사 및 블록을 보완했다. 최종 전체50개 재실행 성공. 로그 .local/workflow/p10-06g-final.log. 현재 모델은 원본/계약·실제 생산자·변경 diff·실행 결과를 재대조했고 기존 검증을 약화하지 않았다. 에이전트 위임/모델·속도 변경 주장 없음.

남은 일: 초기 사본의 RECORDING_FILE_SPEC/RECORDING_TAG 관계 조회와 업무 사본 투영, 영구 삭제 원장·관계/asset 전용 적용, 수신기 및 앱 연결. 전체 P10-06 완료 아님. 코드 커밋·CI는 Git history와 후속 정확 SHA 기록을 따른다.
