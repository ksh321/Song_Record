# P10-06f — 증분 변경 수신: 녹음 응답의 생략 필드 보존

2026-10-01. P10-06 원자 적용 검토 중 실제 생산 코드의 응답 차이를 발견해 세부 ID로 등록했다. e의 저장소 기반 후속이며 폰 APK e4adb7f는 바꾸지 않는다.

근거: RecordingDrafts.snapshot은 핵심 정보와 컨디션을 반환한다. RecordingSaving.save는 여기에 file을 추가하여 변경 로그에 쓴다. RecordingEditing.snapshot 및 Rating/Linking 응답은 tier/tag_ids/tags를 포함하지만 file은 포함하지 않는다. 따라서 후속 편집 payload로 server_payload 전체를 교체하면 이전 저장 응답의 file 명세가 사라진다. 일반 원자 저장 자체의 문제가 아니라 서버별 표현 차이다.

recording_change_projection.dart를 ChangeFeedStore의 RECORDING UPSERT 경로에 연결했다. 이미 알고 있는 file/tier/tag_ids/tags는 후속 payload에서 생략했을 때만 보존한다. 명시적인 tier:null, 빈 태그 배열은 반영한다. 다른 녹음 ID 혼합·짝이 없는 태그 필드·file:null·기존 확정 file 내용 변경은 거절한다. 사본을 만들어 호출자 Map을 변경하지 않는다. 실제 녹음 파일에는 접근하지 않는다.

검증: flutter test --no-pub test/recording_change_projection_test.dart test/change_feed_store_test.dart test/snapshot_download_store_test.dart test/change_feed_response_test.dart test/change_feed_transport_test.dart --reporter expanded **44 PASS**. 관련4파일 flutter analyze --no-pub **No issues found**. 테스트의 빈 List 타입 경고1건을 명시 String 타입으로 보완했다. 현재 모델 별도 검토에서 생략/명시적 삭제 구별, 불변 명세, 깊은 사본, 실제 SQLite server/local JSON과 커서8을 대조했다. 로그 .local/workflow/p10-06f-projection.log. 실제 폰 검증 아님.

현재 계약 조사 결과:
- SONG 생성·편집·대표곡/연결 변경 로그는 일반 Song wire를 기록한다.
- RECORDING은 위 세 가지 표현을 구분해야 한다. 초기 스냅샷의 RECORDING_FILE_SPEC/RECORDING_TAG 관계를 합성하는 읽기 연결은 아직 별도다.
- TAG는 id/name/revision/archived_at/updated_at을 기록한다.
- AccountChanges enum에 있는 PLAYLIST/PLAYLIST_ITEM/RECORDING_ASSET/CONDITION은 그 존재만으로 실제 변경 로그 생산 경로가 완성됐다고 판단하지 않는다.
- DELETE 일반 payload 계약과 초기 DELETION_LEDGER의 영구 표식 투영은 후속 작업이며 자동 적용으로 우회하지 않는다.

남은 범위: 전체 업무 필드 검증(현재 envelope·ID·revision 및 보존 경계만 검증), 초기 스냅샷 관계 합성, 관계/asset·삭제 원장 전용 적용, 수신기·화면 연결. 알려지지 않은 관계를 빈 값으로 꾸미지 않는다. 전체 P10-06 완료 아님. 코드와 정확 SHA CI는 후속 통합 기록으로 확인한다.
