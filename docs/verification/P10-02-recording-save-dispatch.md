# P10-02 의존 순서 전송 — 녹음 저장 완료 경로

2026-10-01, 현재 모델 직접 구현·코드 검토. 새 작업자/검수자 호출 없음.
요구사항 R024/R026/R036, 원본 계획 p00578~580. 기존 RecordingSaving API와 실제 응답을 대조했다.

## 변경과 검토

- mutation_request.dart와 recording_save_contract.dart: 기존 PATCH 저장 완료 API의 SAVED/완료 파일 명세를 원본 본문·op_id 그대로 전송한다. 파일 업로드 완료와 혼동하지 않는다. 미확정 base_revision=0, 연결/등급 혼합 요청, 손상된 파일 명세는 보내지 않는다.
- metadata_response.dart: 저장 응답의 실제 형태(일반 편집 응답의 tier/tags 없음)를 구분한다. ID·revision·SAVED·ACTIVE·파일 명세·변경하지 않은 역사 정보와 정규화한 요청 필드를 대조한 뒤 기존 ACK 트랜잭션에 연결한다.
- metadata_conflict.dart: 저장 상태/파일 전환을 일반 메타정보 비교로 자동 재처리하지 않는다. 원본 큐를 유지한다. 이 누락은 현재 모델의 영향 검토에서 발견해 회귀 테스트로 보완했다.
- recording_save_dispatch_test.dart: SQLite 전송/재개방 시 서버 사본·로컬 SAVED·파일 바이트 보존, 커서 미진행, 잘못된 응답/명세/혼합 경로 거절, 저장 전환 충돌 보류, 서버와 같은 문자열 정규화를 검사한다. 합성 파일이며 실제 폰 녹음 테스트가 아니다.

## 실제 검증

`flutter test --no-pub test/recording_save_dispatch_test.dart test/recording_link_dispatch_test.dart test/recording_tier_dispatch_test.dart test/metadata_conflict_test.dart --reporter expanded`: **30 PASS**. 로그 `.local/workflow/p10-02-save-contract.log`.

초기 분석에서 dynamic 기준 사본의 bool 타입 오류와 스타일 지적을 발견했다. 명시 Map 검증과 중괄호로 보완하며 분석 최종 결과는 아래에 기록한다. 테스트 삭제/약화 없음.

## 남은 범위와 재개

이 변경은 이미 서버 DRAFT 기준 revision을 가진 저장 요청 경로다. 오프라인 CREATE 뒤 base_revision=0인 후속 저장을 실제 ACK 근거로 안전하게 연결하는 경로, 녹음 UI/네이티브 로컬 상태와 큐 연결, 목록·관계·실제 파일 전송은 계속 필요하다. 불변 큐/op_id를 몰래 덮어쓰거나 이 어댑터만으로 전체 P10-02 완료를 선언하지 않는다. 새 폰 실기는 아직 실행하지 않았다.

현재 턴 모델/속도 설정 변경 도구는 미확인. 위험도가 높은 동기화 작업으로 현재 모델이 계약·보존·충돌 영향을 직접 검토했다. 다음은 base_revision=0 후속 요청의 실제 저장/전송 순서와 기존 supersession 제약을 대조해 연결하는 것이다.

최종 분석: flutter analyze --no-pub 변경 Dart 5파일 **No issues found**. 현재 모델 diff 검토 및 관련 회귀30 PASS. 커밋/대상 SHA CI는 다음 기록에서 식별한다.

최종 보존 검토: RecordingSaving은 기존 태그/등급을 수정하지 않지만 응답에서 생략한다. 기존 projectRecordingChange를 재사용해 ACK 때 생략을 삭제로 해석하지 않도록 보완했다. 태그 역사 이름 유지/모순 응답 거절 회귀 포함 최종 관련 테스트31 PASS. 공통 metadata_response_test.dart 및 metadata_dispatcher_test.dart 별도96 PASS(p10-02-save-regression.log), 변경 Dart5파일 분석 No issues found. 앞선30개와31개는 중복 실행이므로 합산하지 않는다.
