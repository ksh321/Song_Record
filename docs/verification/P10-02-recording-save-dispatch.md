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

### 93d1661 커밋·전송 경계 확인 — 2026-10-01

- 대상 SHA: 93d1661c5e035353e02cb809b7e41d40370364bf, 일반 푸시 완료. WORKFLOW-08 기능 흐름 우선 규칙을 함께 보존했다.
- 최초 CI 조회: API contract 36836566600 / Development workflow 36836566509 PASS. CI 36836566652 / Idempotency MySQL 36836566628 진행 중. 전체 CI 통과로 판정하지 않는다.
- P10-02 다음 분석: plan.txt p00578~580의 의존 전송 순서와 실제 dependency_planner.dart를 대조했다. 분류·곡·녹음·관계 순서 검사가 존재한다. MutationRequest.prepare는 song/recording/tag만 전송하며 목록 HTTP 경로를 임의 추측하지 않는다.
- 목록 CRUD 및 항목 쓰기는 원본 P19-01~04(p00869~880), P19는 P10을 선행으로 둔다(p00866). 따라서 P10 완료를 위해 P19 전체 기능을 먼저 구현하는 순환 의존관계를 만들지 않는다. 다음은 기존 planner/dispatcher의 미지원 목록 보존·독립 대상 진행 근거를 검토하고 P10 공통 계약과 후속 P19 어댑터 경계를 구분하는 것이다. 이 분석만으로 전체 P10 완료를 선언하지 않는다.


### 곡·태그까지 오프라인 후속 연결 — 2026-10-01

P10-02 / R002: 기록만이 아니라 곡·태그의 CREATE ACK 뒤 기준 revision=0인 PATCH도 이어져야 한다. `metadata_followup_dispatch_test.dart`에서 실제 계정 SQLite와 전송 실행기를 사용해 6사례를 검사했다. 보완 전 정상/응답 유실 4사례는 후속 미전송으로 실패하고 부모 실패 격리 2사례는 통과했다. 최초 로그 경로 오기는 테스트가 시작되지 않은 명령 오류이며 코드 수정 실패 횟수에 넣지 않는다.

- `metadata_followup_plan.dart` / `metadata_followup_store.dart`로 이름을 일반화하고 SONG/TAG/RECORDING의 동일 대상 ACK 및 현재 사본 일치 근거를 공통으로 사용한다. 새 op_id/기준 revision만 생성하고 원본 payload·시도0·파일·논리 순서는 보존한다. Song 생성 ACK에 저장된 자원 사본은 응답 봉투 모양만 복원해 검증하며 원래 HTTP 상태를 추정해 기록하지 않는다.
- v8은 기존 recording_followups 테이블 이름과 모든 행을 보존하고 삽입 검증 트리거의 허용 entity만 넓힌다. v7의 비어 있지 않은 후속 원장까지 이관 전후 동일함을 확인했다. 사용자 DB/볼륨 초기화 없음. 로컬 스키마 fixture v7은 보완 전 커밋의 원본이다.
- 정상 전송, 응답 손실 후 동일 op_id/body/hash 재시도, 부모 실패 시 자식 대기·다른 대상 진행, 재시작, 미지원 P19 목록 요청과 합성 파일 보존을 확인했다. 이는 실제 폰 조작이나 실제 Spring 서버 연동 결과가 아니다.
- 관련4파일(`metadata_followup_dispatch_test`, `recording_save_dispatch_test`, `recording_followup_conflict_test`, `recording_followup_plan_test`) 20 PASS. 계정/이관/충돌/새 후속 관련5파일 통합58 PASS / 기존 Windows 심볼릭 링크 권한 skip1. 로그 p10-02-metadata-followup-after.log 및 p10-02-metadata-followup-integration.log.
- 확대 검증에서 기존 동시 전송 테스트가 ‘CREATE 뒤에는 더 보내지 않음’을 전제로 한 Completer를 다시 완료해 실패했다. CREATE ACK 직후 원본 보존 검사를 유지하고 이어지는 PATCH 중복 방지/ACK/원본 시도0까지 검증하도록 강화했다. 테스트를 제거하거나 예외를 무시하지 않았다. 최종 HTTP 실행기·이관·곡/태그 후속3파일 38 PASS(p10-02-metadata-followup-review.log). 위 실행들은 중복 범위가 있으므로 합산하지 않는다.
- 변경9파일 analyze No issues found. 현재 모델이 동일 대상/계정·canonical 보류·기존 충돌 순서·불변 원본을 직접 대조했다. 별도 에이전트 검수 아님. 새 코드 CI와 전체 P10 통합은 아직 미완료.

#### P10-CI-SCHEMA 재발 보완

93d1661의 CI 36836566652는 Flutter 스키마 생성 비교 실패, API contract/Idempotency MySQL/Development workflow는 PASS. 이전 같은 문제 이력을 유지하며 이번 CI 재발 1회(기존 1회 포함 누적 2회)를 기록한다. 원인은 로컬 스크립트가 .drift를 CRLF로 다시 써 Git의 LF 속성만으로 작업 폴더 생성 입력이 정규화되지 않은 것이다.

원본 .drift를 LF로 정규화했다. v7 스냅샷은 SQL 문자열47곳의 CRLF→LF만 수정했으며 파싱한 JSON을 대조해 SQL 줄바꿈 이외 차이가 없음을 확인했다. v1~v6는 그대로다. 새 v8도 같은 LF 기준으로 생성했다. build_runner 및 make-migrations --no-test가 Linux와 같은 LF 입력으로 성공했다. canonical_schema_test에 현재 원본/스냅샷 SQL의 LF 검사를 추가하여 로컬에서도 생성 입력 문제를 감지한다. 검사 비활성화/완화 없음. 최종 수정 SHA의 CI 결과는 후속 기록으로 판정한다.


02268882dd57afa60b510f760ec40a032e2a2928 필수 CI4 PASS: 36838603955/36838603995/36838604019/36838603865. 스키마 LF 보정 및 곡/태그 후속 연결의 해당 범위 검증 완료. 전체 P10-02 완료로 확대하지 않는다. 이어진 P10-10 서버 계약 교차 검증에서 숫자 응답 표기 결함을 발견해 보완 중이며 P10-10-two-device-flow.md에 근거를 연결한다.

## 번호순 재개 대조 — 2026-10-01

현재 주 작업은 P10-02 의존 순서 전송이다. P10-04/P10-07은 사용자 예시이며 우선 착수 지시가 아니었다. 기존 완료 이력은 유지한다.

- 원본 plan p00579~580: 분류·곡→녹음→목록·관계→파일, 선행 실패 시 관련 항목만 대기, 미생성 곡 때문에 입력/파일을 버리지 않음. dependency_planner.dart의 phase0/1/2와 실제 참조 검사를 대조했다.
- 실제 실행: `flutter test --no-pub test/dependency_planner_test.dart test/metadata_followup_dispatch_test.dart test/recording_save_dispatch_test.dart test/recording_tier_dispatch_test.dart test/recording_link_dispatch_test.dart --reporter expanded` **36 PASS**, 종료0. 현 작업 폴더의 미커밋 P10-07 변경도 포함된 결과이며 특정 과거 SHA 결과로 꾸미지 않는다. 로그 .local/workflow/p10-02-order-audit.log.
- 숫자 응답 보완 ae8093d와 수신 후 오래된 기준 처리708ac40은 필수 CI4 PASS 기록으로 확인했다. 708ac40 실행은 CI36845969983/API36845970297/MySQL36845970399/Development36845970132.
- 아직 전송 미지원인 목록 HTTP/파일 큐는 원본 P19/P12 후속 경계다. 이를 구현 완료로 주장하지 않으며 P10 자체 공통 의존 계획과 후속 어댑터 완료 기준을 분리해서 남은 공통 연결 유무를 확인한다. 이 대조만으로 P10-02 전체 완료 판정을 내리지 않았다.
- 다음 실제 행동: 의존 계획에서 파일 작업과 미지원 항목이 다른 대상 송신을 차단하지 않는 경계 및 후속 어댑터 등록 지점을 확인하고, 필요한 공통 계층 보완 여부를 결정한다. 새 폰 조작 요청 없음.

### 추가 통합 근거

`dependency_dispatch_integration_test.dart`는 실제 계정별 SQLite와 저장소/송신기를 사용한다. 곡503 실패 중 무관한 태그는 전송되지만 해당 녹음은 시도0으로 보존된다. 재시작 후에도 차단되며 곡 수동 재시도 성공 뒤 녹음이 전송된다. 원본 payload/녹음 UUID/합성 파일 바이트와 ACK 기록을 확인했다. 제품 내부 큐의 실패 격리는 개발 작업 번호의 엄격 순차 운영과 다른 요구사항이다.

`flutter test --no-pub test/dependency_dispatch_integration_test.dart --reporter expanded` 1 PASS, `flutter analyze --no-pub test/dependency_dispatch_integration_test.dart` No issues found. 최초 import 누락으로 컴파일 미실행, ACK 제외 조회를 최종 기록 검증에 잘못 사용한 테스트 오류를 복구 테이블 조회로 수정했고 분석 지적도 해결했다. 실제 서버/폰 실기로 확대하지 않는다. 제품 코드 변경 없음.

현재 검증 커밋9469638501614583d15de2f23b471e21e6c385d2는 일반 푸시 완료. 정확 SHA 조회에서 API36848991215/Development36848991024 PASS, CI36848991358/MySQL36848991137 PENDING을 관측했다. 이는 당시 상태이며 최종 통과 아님. 최신 엄격 순차 규칙에 따라 뒤 번호 작업은 진행하지 않고 해당 실행들의 종료 결과 확인부터 재개한다. 사용자 직접 행동 없음.

후속 관측: 같은9469638의 MySQL36848991137도 PASS로 바뀌어 필수3개 PASS, CI36848991358만 PENDING이다. 3회 이상 연속 재개에서도 같은 정확-SHA CI 완료 조건이 미충족이고 최신 사용자 순차 규칙상 뒤 작업은 실행할 수 없다. 반복 조회를 지속하지 않고 이 외부 CI 결과 대기로 Goal을 blocked 처리한다. 실패/취소로 판정하거나 CI를 재실행하지 않는다. 재개 시 github-check.ps1 -Commit 9469638501614583d15de2f23b471e21e6c385d2로 기존 실행을 확인하고, 통과하면 P10-02 완료 조건 대조부터 이어간다. 사용자 직접 행동은 없으며 새 폰 알림/체크리스트를 만들지 않는다. P10-07 미커밋12파일 및 이번 문서/체크리스트 변경은 보존했다. 로컬 실행 중 명령 없음, 원격 CI만 실행 중이다.

### CI 최종 결과 — 2026-10-01

9469638501614583d15de2f23b471e21e6c385d2의 필수 네 CI 모두 PASS를 실제 확인했다: CI36848991358, API36848991215, MySQL36848991137, Development36848991024. 위 PENDING/Goal 차단은 당시 기록이다. CI 차단은 해소됐으나 P10-02 전체 완료를 선언하지 않는다. 다음 제품 행동은 앞서 기록한 공통 의존 계획/후속 어댑터 경계 대조다. 사용자 별도 요청으로 WORKFLOW-02 CI 알림 도구를 구성했으며 이 알림 도구의 새 커밋 CI는 별도로 확인한다.

### P10-02-NEXT 보존·미지원 경계 검증 보강 — 2026-10-02 / IMPLEMENT

기존 P10-02a/b/c/d 및 생성 ACK 뒤 후속 수정/저장 연결의 구현·완료 이력을 유지한다. 작업 시작 기준은 `ff667c3`이며 제품 미커밋 변경은 없었다. 현재 단계에서는 아래 테스트 두 파일과 이 기존 검증 문서만 편집했다. 앱 실행 코드·서버·DB 스키마·실행기에는 변경이 없다. 새 검사의 실행 결과와 별도 REVIEW 단계는 아직 대기이며 이 절은 통과 기록이나 P10-02 최종 완료 판정이 아니다.

| 계획 기준 | 구현한 검증 내용 | 파일 |
|---|---|---|
| A1, R036 | 목록 항목의 목록·곡, 녹음 태그 관계의 녹음·태그 각각에 대해 부모 후보와 실제 승인 기준을 구별. 한 부모 누락·삭제·잘못된 참조, 전체 메타정보 단계 순서, canonical 별칭의 논리적 선행 보류 검사 추가 | `apps/mobile/test/dependency_planner_test.dart` |
| A2/A3, R002/R026/R036 | 기존 곡503 실패 격리 검사를 강화. 합성 파일을 계정 영속 경로에 저장하고 `recordFileAndJournal`로 등록. 다른 계정의 접근 거절, 새 관리자로 재개방, 부모 수동 재시도·ACK 전후 원본 큐·입력·파일 인덱스·저널·해시·바이트 비교 | `apps/mobile/test/dependency_dispatch_integration_test.dart` |
| A2/A5, D06 | 태그503 실패 동안 녹음 `PATCH tag_ids`는 시도0으로 대기하고 무관한 곡은 진행. 재개방 뒤 같은 frozen 태그 요청을 재시도하고 태그 ACK가 DB에 반영된 후 관계 PATCH 전송을 검사 | 같은 통합 테스트 |
| A4/A5/A7 | 목록·목록 항목·녹음 태그·파일 명세·파일 자산 미지원 요청을 먼저 큐에 넣고 뒤의 곡·태그·녹음은 제한된 전송 회차로 처리. 미지원 원문·로컬 사본·시도0·자동 예산0·wire 미생성, 남은 요청의 즉시 재예약 없음, 재개방 후 보존 및 송신 중 커서 미전진 검사 | 같은 통합 테스트 |

파일 fixture는 실제 오디오가 아닌 합성 4바이트다. 계정 경로/체크섬 검증을 통과하도록 등록하지만 오디오 디코딩·네이티브 녹음·폰 실기를 검증했다고 하지 않는다. 기존 통합 검사의 저장소 밖 단독 파일 확인을 실제 파일 인덱스·저널 경로로 강화했으며 기존 부모 실패/독립 태그/재시도/ACK 검사는 유지했다. 임시 디렉터리 이름과 해석된 경로가 시스템 임시 디렉터리 아래인지 확인한 뒤 해당 fixture만 정리한다. 재시도 시계는 고정하여 테스트 실행 시간에 따른 자동 재시도 진입을 배제한다.

#### 공통 전송 계층과 후속 연결 위치

| 단계 | 현재 코드 위치·책임 |
|---|---|
| 일관된 입력과 의존 계획 | `AccountStore.dispatchSnapshot`이 계정별 큐·서버 기준·mapping을 읽는다. `LocalRepository.planDispatch` / `DependencyPlanner.plan`은 논리 순서, 대상별 선행 작업, 참조 승인·삭제·보류와 단계 정렬을 계산한다. ready는 HTTP 지원이나 서버 승인 표시가 아니다. |
| 실제 전송 준비·선점 | `AccountStore.claimMutation`은 트랜잭션 안에서 기존 metadata followup을 구체화하고 재시도 정책을 적용한 새 계획을 계산한다. `RetryControls.claim`은 `MutationRequest.prepare` 또는 보존된 frozen 요청을 사용한다. 지원하지 않는 최초 요청은 시도/예산/wire를 만들지 않고 건너뛴다. |
| 응답과 원자적 ACK | `MetadataDispatcher.dispatch`는 계정 fence와 인증 소유자를 확인하고 응답을 `decodeMetadataSnapshot`으로 검사한다. `AccountStore.acknowledgeMutation`은 소유한 시도의 서버 사본·큐 ACK를 원자적으로 반영한다. canonical 응답은 기존 별도 매핑 트랜잭션을 사용한다. 다음 claim에서 계획을 다시 계산한다. |
| 실행 재예약 | `AccountStore.nextDispatchAt`은 초기/수동 후보에 실제 요청 준비 가능 여부를 함께 확인한다. 미지원 요청만 남은 상태를 실행 가능한 송신으로 간주하지 않는지 통합 테스트에 포함했다. |
| 실제 파일 전송 | 현재 `RECORDING_FILE_SPEC` / `RECORDING_ASSET` 큐는 공통 planner의 unsupported 보존 대상이다. 이를 파일 업로드 성공이나 파일 단계의 실제 송신 검증으로 기록하지 않는다. P12-05가 승인된 정보 이후 실제 원본 전송과 실패·취소·인증 만료 보존을 연결해야 한다(plan p00654~p00656). |
| 목록·관계 쓰기 | 공통 planner는 참조 순서를 검사하지만 `MutationRequest.prepare`는 목록 및 독립 관계 HTTP 경로를 제공하지 않는다. P19-01~04가 목록 CRUD·등록곡/후보 추가·연결의 실제 어댑터와 ACK 계약을 연결해야 한다(plan p00866~p00880). 녹음의 태그 연결은 현재 지원되는 `PATCH tag_ids` 경로로 별도 검증한다. |
| 녹음 입력 연결 | P18-02가 네이티브 저널·파일·DRAFT 큐를, P18-04가 실제 저장 UI를 연결한다(plan p00837~p00845). 이번 fixture 작성은 그 기능 구현 완료가 아니다. |

원본 P10-02(plan p00578~p00580), 설계 4.2(p00291~p00294), R036의 순서와 입력·파일 보존 기준을 유지한다. 후속 P12/P18/P19 작업을 앞당기거나 완료 처리하지 않는다. D06의 과거 컨디션 보존 및 승인된 고정 컨디션 정책도 변경하지 않는다.

#### 실행·인계 상태

- 현재 모델이 직접 편집했으며 위임은 없다. 동기화·계정 격리·DB 보존 검증이므로 계획의 위험도는 `sensitive`다. 런타임 모델 설정을 변경했다고 주장하지 않는다.
- 파일 편집 명령으로 Dart formatter를 실행하여 두 테스트 파일에 포맷을 적용했다. 종료 시 SDK 텔레메트리 로그 정리 권한 오류가 발생하여 명령 종료 코드는 1이었다. 테스트/분석 실패로 분류하거나 코드 수정으로 환경 오류를 우회하지 않는다.
- 후속 제어기 인계: 제어기를 관리하는 AI가 동일 `dart format` 명령을 실제 사용자 환경에서 직접 실행하여 종료 코드 0을 확인했다고 전달했다. 이 결과에 따라 포맷 환경 대기는 해소하며 추가 승인을 요청하지 않는다. 현재 모델이 해당 재실행을 직접 관측한 결과 또는 테스트 통과로 바꾸어 기록하지 않는다.
- 계획의 `dependency-tests`, `regression-tests`, `analyze`, `sources-check`, `diff-check`는 제어기가 실행한다. 이 IMPLEMENT 호출에서는 실행하지 않았으며 새 PASS 수치나 대상 SHA CI 결과가 없다. 구현 후 별도 코드 검토도 제어기의 REVIEW 단계에 남는다.
- 새 폰 실기는 불필요하다. 기존 사용자 확인 범위를 유지하며 사용자 DB 초기화·앱 삭제·재설치·새 정책 선택이 없다. Git 쓰기·알림·CI 조회는 수행하지 않았다.

### P10-02-NEXT 최종 검증 기록 — 2026-10-02 / FINALIZE

대상 SHA는 `38fa6961387e9846797c977b9944af4c5421ff4a`다. FINALIZE 시작 시 HEAD·로컬 origin/main이 대상과 같고 작업 트리는 깨끗했다. 현재 소스 지문 `6849078c05481f7ee37f31b94eb805b81571d7793f5db604f6d027be63cfcd28`이 제어기의 검증 지문과 일치했다. 아래는 제어기가 실행한 로그를 현재 모델이 읽어 확인한 결과이며, 앞선 IMPLEMENT 절의 검증 대기를 해소한다.

| 검사 | 실제 명령과 결과 | 실행 ID |
|---|---|---|
| dependency-tests | `flutter test --no-pub --reporter json test/dependency_planner_test.dart test/dependency_dispatch_integration_test.dart` — 21 PASS, 실패·건너뜀0 | `4fdc5cd6-3eb8-494a-9934-ab9db13315ff` |
| regression-tests | `flutter test --no-pub --reporter json test/local_repository_test.dart test/metadata_dispatcher_test.dart test/metadata_followup_dispatch_test.dart test/recording_followup_plan_test.dart test/recording_followup_conflict_test.dart test/recording_save_dispatch_test.dart test/recording_tier_dispatch_test.dart test/recording_link_dispatch_test.dart test/mutation_retry_test.dart` — 80 PASS, 실패·건너뜀0 | `ffeecc6c-c432-43e5-add4-89c8243a686f` |
| analyze | `flutter analyze --no-pub test/dependency_planner_test.dart test/dependency_dispatch_integration_test.dart` — No issues found | `0642c41d-70b7-46b1-9933-a6e892e2b95f` |
| sources-check | `python tools/index_sources.py --check` — 저장소 원본6개 해시·검색 색인 PASS | `d77b72b9-592f-49d1-abad-fde2a25bd2c7` |
| diff-check | `git -c safe.directory=C:/Users/ksh/Documents/GitHub/Song_Record diff --check` — PASS | `7c9307a4-9644-4d08-be77-2dec5dccae61` |

모든 명령 종료 코드는0이다. Flutter 명령 작업 디렉터리는 `apps/mobile`, 나머지는 저장소 루트다. 원시 로그는 `.local/workflow/runs/sequential/commands/<실행 ID>/`에 있다. diff의 LF→CRLF 안내는 실패가 아니다.

현재 모델이 원문·승인 변경·전체 diff·실행 로그·회귀·데이터 보존·미연결 범위를 별도 REVIEW 단계에서 대조하여 승인했고 지적은0건이다. 동기화·계정 격리·DB 보존을 다루므로 위험도 sensitive를 유지하며 위임 또는 모델 설정 변경을 주장하지 않는다. **P10-02-A1~A7 모두 충족**: A1 참조별 ACK·논리 순서, A2 부모 실패 격리·수동 재시도, A3 계정 전환/재개방 시 등록 파일·저널·입력 보존, A4 미지원 원문·시도/예산 보존과 즉시 재예약 방지, A5 기존 후속 원장·frozen 재전송·커서 분리 회귀, A6 공통 계층과 후속 연결 경계 기록, A7 임시 자료 정리 범위·기존 검사 유지·결과 및 검토 기록을 확인했다. 승인 계획상 새 실기는 불필요하며 기존 사용자 확인을 유지한다.

제어기가 저장한 `.local/workflow/ci-38fa6961387e9846797c977b9944af4c5421ff4a.json`(2026-10-02 08:56:34 UTC)을 읽어 대상 SHA와 push 기준 `1227a1694c9c44de8ded5b194e2a658856c1df4d`를 대조했다. 전체 판정 PASS, [CI36985529233](https://github.com/ksh321/Song_Record/actions/runs/36985529233)의 필수 `Scope changed files` 및 `Flutter analyze, test, and Android build`가 success다. API contract·Idempotency MySQL·Development workflow는 NOT_APPLICABLE이며 CI 내부 서버/MySQL job의 skipped도 제외 범위다. 이를 통과 실적으로 세지 않으며 이 보고서는 서버 브랜치 보호 규칙 확인 증거가 아니다. 이번 호출에서 원격 CI 조회는 하지 않았다.

P10-02-NEXT의 승인된 남은 범위는 충족했다. P12-05 실제 파일 전송, P19-01~04 목록 쓰기·관계 연결, P18-02/04 녹음 입력·저장 UI는 앞선 표의 후속 통합 조건으로 유지하며 전체 P10 또는 후속 기능 완료를 주장하지 않는다. 이 FINALIZE는 기존 검증 문서와 progress만 갱신한다. 제품·실행기·기존 ID/완료 이력을 바꾸거나 사후 기록 전용 커밋을 만들지 않고 최종 상태 반영을 제어기에 인계한다.
