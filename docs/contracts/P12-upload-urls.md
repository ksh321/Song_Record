# P12-04 업로드 PUT URL 계약

원본: 구현설계서 v1.11 8.1~8.3 / 12.5, 계획서 P12-04. R068. P12-03 승인 조건 유지.

- `POST /v1/recordings/{id}/uploads`: 인증·X-Device-Id·UUID Idempotency-Key 필수. JSON `expected_size` 정수와 `sha256` 소문자 64자리만 받는다.
- 새 전송 응답 201: `attempt_id`, `state=UPLOADING`, `put_url`, `headers`(이름→값 목록), `expires_at`(URL 만료), `attempt_expires_at`(최초 생성+24시간).
- 같은 명세로 이미 STORED이면 200 `{state: STORED}`. 추가 예약·서명 없음.
- `POST /v1/uploads/{attemptId}/renew-url`: 같은 인증·기기·멱등 키 필요, 본문 없음. 200으로 같은 응답 필드. 새 요청 키는 새 URL 발급이며 기존 시도·예약·24시간 만료는 유지한다.
- 같은 멱등 키 재시도는 원래 응답을 그대로 반환하므로 추가 발급 횟수에 포함하지 않는다. 재생된 주소가 만료했으면 renew-url에 새 요청 키를 사용한다.
- URL 최대 10분, 시도 만료가 가까우면 그 안으로 축소한다. 1초 이하 남은 시도는 HTTP 410 UPLOAD_EXPIRED. RESERVED/UPLOADING만 재발급하며 VERIFYING/종료 상태는 UPLOAD_STATE_CONFLICT. 만료 시 예약 해제·새 시도 허용은 P12-10 대조 절차가 담당한다.
- 재발급도 현재 녹음 수명·보관 사유·명세·소유권을 재검사한다. 초기/재발급 합산 계정별 분당 10회. 서명 실패 시 예약·일일 사용량·발급 횟수·멱등 영수증을 함께 롤백한다.
- 앱은 HTTPS PUT으로 로컬 원본 바이트를 보낸다. 반환 헤더 중 Host는 HTTP 라이브러리가 URL에서 설정한다. 앱 인증 Bearer를 R2로 전달하지 않는다. R2 비밀키와 최종 객체 쓰기 권한은 앱에 주지 않는다.
- 주소는 일시적 쓰기 권한이므로 로그·분석·오류 메시지·화면 공유에 포함하지 않는다. 응답 Cache-Control은 no-store. 멱등 응답에는 서버 DB의 기존 영수증 보존 정책이 적용되지만 URL 자체의 유효기간은 연장되지 않는다.
- 서명은 로컬 계산이며 DB 잠금 중 네트워크 전송하지 않는다. PUT 성공은 STORED 판정이 아니다. 실제 바이트 검증·최종 확정은 후속 P12-06~09에서 연결한다.

검증: URL 재발급/24시간 불변·계정 격리·승인 철회·멱등 재시도·발급 한도·서명 실패 롤백, SDK 실제 서명 임시 키/TTL 검사. 실제 개발 R2 서명 PUT은 별도 일회용 입력 검사 결과로 확인한다.
