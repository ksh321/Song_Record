# P12-02/03 업로드 예약과 승인 경계

원본 설계서 8, 11, 12 및 코드구현계획서 P12-02/03의 내부 구현 계약이다. HTTP 최종 계약의 PUT URL 발급은 P12-04에서 연결한다.

- 입력: 인증된 계정·기기, 녹음 ID, expected_size(1~6,291,456), 소문자 64자리 sha256. 서버 RecordingFileSpec과 일치해야 한다.
- 현재 ACTIVE/SAVED·유효 파일 명세·자동 역할/고정/보존 사유를 확인한다. 자동 역할은 현재 후보로 계산한다. 다른 계정은 RESOURCE_NOT_FOUND, 비대상은 NOT_CLOUD_TARGET, 명세 불일치는 FILE_SPEC_MISMATCH.
- 기존 같은 명세 STORED는 상태만 반환한다. 기존 활성 시도는 기존 attempt와 최초 만료를 반환하고 추가 예약·일일 허가를 만들지 않는다. 동일 Idempotency-Key/바디는 영수증 재조회이며 변경 바디는 IDEMPOTENCY_CONFLICT.
- 새 예약은 글로벌→계정 동기화→요금제·사용량 잠금 아래 개인/전체 한도와 두 슬롯을 검사하고 recording_upload 및 두 reserved_bytes를 함께 기록한다. 용량 초과 QUOTA_EXCEEDED, 예산 잠금 UPLOAD_BUDGET_LOCKED, 동시 슬롯 초과 UPLOAD_CONCURRENCY_LIMIT.
- 일일 승인량은 UTC 일 104,857,600바이트, 초과 시 429 UPLOAD_DAILY_LIMIT. 승인량은 시도 취소로 돌려주지 않는다.
- 초기 발급 허가는 새 승인과 함께 기록한다. URL 재발급은 공유 issuePermit을 소비해야 한다. 최근 60초 10회를 초과하면 429 UPLOAD_RATE_LIMITED. 실제 발급 실패 시 바깥 트랜잭션을 롤백한다.
- 현 단계에는 외부 공개 업로드 Controller·PUT URL이 없다. P12-04는 이 승인 결과와 실제 서명 URL을 하나의 명령 결과로 연결해야 한다. 기존 시도 재조회가 새 URL 발급을 의미하지 않으며 실제 새 URL에는 반드시 발급 허가를 적용한다.
- 예약 확정·해제·객체 삭제는 후속 원본 P12-09/10 범위다. 원본 바이트 및 기존 저장 파일을 변경하지 않는다.


P12-04 후속: 공개 HTTP 연결은 `UploadController`/`UploadUrls`에서 승인·서명·영수증을 하나의 트랜잭션으로 처리한다. 계약은 `docs/contracts/P12-upload-urls.md` 참조. 과거 본문의 공개 HTTP 미연결 설명은 P12-03 완료 당시 범위다.
