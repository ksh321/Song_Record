# P20-01 삭제 미리보기

## 승인·원본·범위
- 2026-10-11 사용자 `p20ㄱ`: P20-01~10 순차 원수 실행. 요청 6.1 Sol/medium, 현재 모델 직접 구현·별도 검토. 추가 AI 호출 없음.
- 원본 계획서 문단901~903, 설계서 문단535·913~918, R091 대조. 이전 P10·P13·P19 완료 근거 보존.
- GET /v1/songs/{id}/delete-preview와 후속 삭제 트랜잭션의 재확인 함수. 실제 휴지통 변경은 P20-02/04, 화면은 P20-10에서 연결한다. 현재 사용자 데이터 삭제 없음.

## 동작·변경
- 같은 계정 ACTIVE 곡의 ACTIVE 연결 녹음만 계산한다. 휴지통·미연결·다른 계정·타 기기의 미동기화 정보는 포함하지 않는다. scope=SERVER_SYNCED_ONLY.
- recording_count, server_bytes(STORED/DELETING 실제 사본), pinned_count(현재/대기 고정 녹음의 중복 없는 수), preview_version. 객체 키·녹음 ID는 응답에 포함하지 않는다. Cache-Control no-store.
- preview_version은 계정·곡·revision·대표 연결·녹음 ID/연결/상태·파일 generation/revision/크기·고정 슬롯에 묶는다. 개수/크기가 같아도 대상 교체 시 무효화된다.
- 계정 sync 잠금·READ_COMMITTED 트랜잭션으로 일관된 범위를 읽는다. 후속 삭제는 같은 계정 잠금 트랜잭션에서 requireUnchanged 호출 후에만 변경한다. 불일치·잘못된 확인값은 409 DELETE_PREVIEW_CHANGED, 잘못된 실행 위치는 거절한다.
- 변경: SongDeletionPreview, SongController/Configuration, OpenAPI, SongDeletionPreviewTests, 공통 SongCreationTests의 거래 관리자 등록, MySqlIdempotencyTests의 실제 마이그레이션 자산·고정·변경 확인.

## 검증·검토
- API build --offline 전체 PASS(1분7초). 미리보기 5개 PASS: 서버 범위/부작용 없음, 동일 개수의 대상 교체, 파일·고정·연결·곡 revision 변경, 소유권/휴지통/인증 우선, 트랜잭션 밖 재확인 거절.
- OpenAPI 계약 PASS: local references/security/7 wire examples/141 schema boundary cases.
- 별도 검토에서 GET의 격리를 READ_COMMITTED로 명시해 잠금 대기 전의 오래된 스냅샷 사용을 막았다. 실제 MySQL 검사 추가 시 테스트 UUID 변환 import 누락을 수정했다. 최종 영향 검사는 아래 결과로 확인한다.
- P20-01에는 화면·새 기기 동작이 없어 설치본 검사 해당 없음. 삭제 화면과 실제 취소/확정은 P20-10에서 필수 검증한다. 기존 설치본 검사를 반복 요청하지 않는다.
- 실기 해당 없음은 통과 실적이 아니다. 실제 MySQL 실행 및 최종 SHA 필수 CI는 푸시 후 확인한다.

## 학습 개념
- 삭제 확인은 숫자만 비교하면 같은 개수의 다른 데이터가 삭제될 수 있다. 실제 대상과 revision에 묶인 확인값을 서버 트랜잭션에서 다시 비교해야 한다.

- 최종 영향검사5개 PASS. 현재 모델 별도 검토: 계정 범위·삭제 권한 분리·서버 사본 집계·현재/대기 고정 중복·READ_COMMITTED와 sync 잠금·대상 교체 검출·원본 API·데이터 변경 없음 대조. 지적 해결.

- 최초 실제 MySQL CI38112936974: 시험 pin_slot의 operation_id/requested_at 누락으로 ck_pin_request 위반. 제품 판정 실패와 구분하며 제약은 유지한다. 정상 고정 기록처럼 필수 요청 정보를 추가, API 크기/고정 집계 단위 설명을 명시. 최종 SHA에서 재확인. 원인 P20-01-MYSQL-FIXTURE-01 수정 시도1, 사용자 개입 불필요. 이전 감시는 수정 SHA로 대체하기 위해 종료.
