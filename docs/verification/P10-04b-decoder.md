# P10-04b-DECODER — canonical 응답 검증 기반

계획 P10-04(p00584~p00586), 설계 p00293의 원자 매핑 전 입력 경계다. P10-04a 저장 구조와 별개로 기존 P10-02b 응답 검사 코드를 재사용한다. 전체 매핑 구현 완료를 뜻하지 않는다.

- `metadata_response.dart`: 기존 dispatcher의 `_snapshot`을 원문에서 공용 함수로 추출했다. 성공·409 검증 조건을 유지한다. 새 `CanonicalSongReceipt.decode`는 SONG CREATE/POST/200/created=false/실제 wire의 TJ 요청/다른 canonical UUID/ACTIVE/전체 필드를 확인한다. TJ 번호는 기존 TjNumber 계약으로 검사한다. 원문 응답을 보존하고 snapshot을 불변 사본으로 노출한다.
- `metadata_dispatcher.dart`: 성공·충돌의 기존 검증 호출만 공용 함수로 교체했다. ACK·보류·401/403 callback와 자동 후속 전송 제어는 바꾸지 않았다. 새 receipt를 실제 매핑에 연결하지 않았다.
- 검증된 객체는 응답 형식의 근거이며 서버 인증이나 DB 요청 소유권의 대체가 아니다. 다음 트랜잭션에서 계정 lease·wire·attempt 소유권을 확인해야 한다.
- 서버 SongCreation은 인증 계정의 검증된 proof 번호로 중복 조회 후 source_type/번호/ACTIVE를 검사한다. source_token을 TJ 번호로 추측 비교하지 않는다.

## 실제 검증

`dart format` 적용. `flutter test --no-pub test/metadata_response_test.dart test/metadata_dispatcher_test.dart test/mutation_retry_test.dart test/sync_controller_test.dart --reporter expanded`: **147 통과**. `flutter analyze --no-pub`: No issues found. 원문 보존·불변성·잘못된 envelope/필수 필드/번호/상태/UUID·기존 성공/PATCH/충돌과 지연 401/403 회귀 포함.

Worker Astra/high(동기화 응답 경계), 별도 Reviewer Astra/high 검수에서 범위 내 차단 결함 없음. 기존 조건과 인증/ACK/충돌 보존, 불변 snapshot·원문 보존을 대조했다. 리뷰 입력에 identifiers.dart와 분석 원문이 없어 그 세부 규칙/실행은 검수자가 독립 확인하지 못했다. master는 실제 domain 코드와 실행 결과를 확인했고 대상 SHA CI로 후속 확인한다. default/Fast 끔 요청, 실제 tier 미확인. 상세 로그 `.local/workflow/p10-04b-decoder-test.log`. 커밋·해당 SHA CI 전 완료 판정하지 않는다. DB/파일을 수정하는 실기나 추가 폰 조작을 요청할 변경이 아니다.

다음: 이 객체를 단일 매핑 트랜잭션에 연결하면서 개인 편집/참조/늦은 ACK/보류 순서를 함께 보존한다. 현재 CANONICAL_MAPPING_REQUIRED 정책은 유지한다.

## 커밋·CI 최종 판정

대상 **6f146e150837a178ec96e9ddb3a1db8f1ff9e9e6** 일반 커밋·push 후 필수 CI 4개·필수 job 모두 success: [CI 36575497981](https://github.com/ksh321/Song_Record/actions/runs/36575497981), API contract 36575498123, Idempotency MySQL 36575497682, Development workflow 36575497774. **P10-04b-DECODER 완료**. 이전 절의 커밋/CI 대기는 검증 전 이력이다. P10-04 전체 매핑과 새 폰 실기는 완료로 확대하지 않는다.
