# P12-06 완료 요청과 검증 바이트 확보

원본 계획 XML p00657~659, 설계 p00481~502·p00889~894, R069. 기존 JobQueue·IdempotentMutations·UploadReservations를 재사용한다. DB 스키마 변경 없음.

## 요청

`POST /v1/uploads/{attemptId}/complete`, Authorization·X-Device-Id·Idempotency-Key, 본문 없음.
인증·소유권 확인 후 UPLOADING/VERIFYING의 만료 전 시도만 접수한다. HTTP 202 JSON은 attempt_id·state=VERIFYING·job_id. 이미 COMMITTED이면 200/COMMITTED. 동일 HTTP op는 저장된 응답을 재사용하고, 다른 op도 attempt 기준 같은 UPLOAD_VERIFY 작업에 합류한다. 응답 기록·작업 삽입·VERIFYING 전이는 한 트랜잭션이며 예약 바이트·사용량·자산 상태를 바꾸지 않는다.

## 작업자 연결 경계

`UploadVerification.prepare(lease, consumer)`는 기존 JobRunner의 준비 단계에서 호출한다. 작업 소유권·만료·계정 ACTIVE·녹음 ACTIVE/SAVED를 확인하고 서버가 소유자/녹음/시도에서 만든 임시 키만 사용한다. worker 역할의 R2 streaming GET으로 실제 바이트를 읽는다. HTTP HEAD·크기 헤더·경로 문자열을 검증 결과로 신뢰하지 않는다.

다운로드는 6MiB+1바이트에서 상한을 판정하고 넘으면 중단한다. 공급자 스트림은 abort하여 남은 과대 객체를 배출하며 읽지 않는다. 최대 2개 준비 작업, 단조 시계 60초 및 기존 SDK 연결/읽기/호출 제한을 적용한다. 매 청크 전후 lease를 대조한다. 원본은 제한된 메모리 안에서 읽기 전용 바이트 뷰로 다음 검증 단계에 넘기고 파일·URL·키·원본 바이트를 로그에 남기지 않는다. 실제 동일 바이트를 다음 단계에서 사용해야 하며 임시 객체를 다시 GET하여 확정하면 안 된다.

```java
runner.runOnce(JobQueue.Type.UPLOAD_VERIFY,
    lease -> verification.prepare(lease, validationAndFinalization));
```

validationAndFinalization은 P12-07~09의 실제 검증·최종 객체 작성·DB 효과를 제공하는 연결 지점이다. P12-06에는 이를 대신하는 성공 callback이나 스케줄러를 등록하지 않는다. 이 단계만으로 작업 SUCCEEDED·업로드 COMMITTED·파일 STORED를 만들지 않는다. 실제 자동 소비·오디오 디코딩·최종 확정은 후속 단계가 연결된 뒤 활성화한다. 앱의 P12-05 PUT 성공 대기 상태를 보관 완료로 바꾸지 않는다.

## 검증

같은 DB 시나리오를 H2와 전체 migration MySQL에 적용한다. 중복/동시 요청 작업 1개, 실패 rollback, 다른 계정 거절, RESERVED/만료 거절, 실제 바이트 전달과 읽기 전용 뷰, 계정 변경/lease 만료 차단, 과대·미존재 객체 실패, 예약·자산 보존을 검사한다. SDK 경계는 worker GET 및 API 역할 거절·HEAD 미사용을 확인한다. 실제 R2 자격 증명이나 사용자 녹음은 사용하지 않는다.
