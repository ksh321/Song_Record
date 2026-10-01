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

### 2026-10-01 진행 중: 오프라인 생성 뒤 후속 저장

아직 미커밋인 후속 연결: recording_followup_plan.dart, recording_followup_store.dart, local_schema.drift v7 및 생성 파일, AccountStore/mapping_eligibility. 원본 base_revision=0 큐는 보존하고 CREATE ACK·현재 서버 사본이 일치할 때 새 op_id를 추가하여 원래 논리 순서로 전송한다. 재시작 뒤 읽기 전용 스케줄러 미리보기도 새 후속을 찾는다. 복구 내보내기에 recording_followups 포함. 실제 녹음 화면/네이티브 저장 연결은 아직 남았다.

실제 검증: recording_save_dispatch_test + recording_followup_plan_test 12 PASS. 이후 account_store/mutation_retry/canonical_schema/conflict_resolution_schema/recording_save_dispatch/recording_followup_plan 6파일 통합83 PASS, Windows 관련 기존 skip1. 변경7파일 analyze No issues found. Drift build_runner 및 make-migrations --no-test 성공. v1~v6→v7의 기존 행·wire·budget·cursor·합성 파일 보존 확인. 최초8실패는 스키마 기대 버전6→7 차이였으며 검사를 삭제하지 않고 v6 fixture/이관 검사를 추가했다. 로그 p10-02-followup-regression.log. 세션80932 종료0.

남은 현재 모델 검토: 새 후속 원장에 대한 직접 삽입/변경 차단과 응답 손실 재시도, 여러 후속 요청 순서 및 기존 conflict-resolution/supersession과 결합된 순서를 더 대조해야 한다. 현재 derive는 일반 RECORDING PATCH도 허용하므로 저장 전환 밖까지 암묵적으로 완료 처리하지 않는다. 이 검토와 실제 녹음 입력 연결 전까지 커밋/전체 완료 판정하지 않는다. 사용자 데이터 DB에 새 스키마를 직접 적용하거나 폰에 설치하지 않았다.

앞선 5a985fc8eac558e757af85a3c4bb07f1effe8d79 필수 CI4 PASS: 36833191071/36833191092/36833191093/36833191193. 현재 미커밋 후속 구현의 검증 근거로 확대하지 않는다.

### 후속 연결 묶음 검증·현재 모델 검토 결과

- 최종 관련8파일(`account_store_test`, `mutation_retry_test`, `canonical_schema_test`, `conflict_resolution_schema_test`, `conflict_resolution_store_test`, `recording_save_dispatch_test`, `recording_followup_plan_test`, `recording_followup_conflict_test`) **97 PASS / 기존 skip1**. 이전83/25와 중복 범위이므로 합산하지 않는다. 로그 p10-02-followup-final.log. 변경10파일 analyze No issues found.
- 응답 유실 후 동일 새 op_id/body/hash 재시도, 앱 재시작 후 후속 감지, 원본 base_revision=0/시도0 보존, 복구 내보내기 및 후속 원장 삭제/수정/교체 금지를 확인했다.
- 일반 메모 후속에서 충돌이 생기면 명시 해결 후 다음 저장 요청이 이어지는 조합도1 PASS. 기존 conflict-resolution이 새 후속 요청의 물리적 생성 위치로 순서를 옮기지 않도록 logical_order 상속을 수정했다. v6→v7은 기존 트리거 정의만 교체하며 행은 삭제하지 않는다. 최초 조합 테스트의 오류 봉투가 실제 서버 형식과 달라 fixture를 보정했다.
- ACK에는 원래 HTTP status가 보존되지 않으므로 201을 지어내 revision1로 강제하지 않는다. 이미 검증·저장된 자원 snapshot의 성공 형식으로 재검증하며 잘못된 후보는 해당 대상만 보류한다.
- v7 스냅샷은 이번 미커밋 생성본만 .local에 보관 후 재생성했다. 기존 v1~v6 스냅샷 보존. 테스트용 v6 SQL은 변경 전 HEAD의 원본 schema에서 가져왔다.
- 원본 계획 대조로 범위를 정정: 녹음 화면/네이티브 저널과 DRAFT 큐 저장은 P18-02, 필수 입력·SAVED UI는 P18-04, 실제 파일 업로드 큐는 P12-05다. 앞서 이를 P10-02에서 즉시 UI까지 구현한다고 설명한 것은 범위가 과했다. 이번 작업은 P10-02 전송 계층의 생성→후속 수정/저장 연결이며, 후속 계획 작업의 미구현을 완료로 간주하지 않는다. 다음은 같은 P10-02의 목록·관계 전송 선행 계약/서버 위치 대조다.
