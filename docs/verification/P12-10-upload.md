# P12-10 실패와 만료 복구 (원수)
- 원본 계획 p00669~671, 설계 p00499~502. R069/R072/R073. P12-09 dc90acebefa782e9daf5155d922490fce30f4c52 필수 CI 완료 후 원수 finish→begin, 요청·관측 gpt-6.1-sol/medium. 시작 원격/main 같은 SHA. 측정 훅 lock은 기존 로그 감시의 짧은 점유를 재시도로 해결, 추가 모델 호출 없음.
- UploadFinalization.recover/UploadFinalObjects.read/R2Storage: 사전 final key 실제 바이트 조회→크기·해시·오디오 재검증→현재 정책/lease 확정. 임시 객체가 없어도 동일 시도 복구. final write/read를 공유60초 Future 경계로 제한, 실제 작업 종료까지 전역 슬롯 유지. 초과 스트림 abort, 메타데이터만으로 신뢰하지 않음.
- UploadRecovery/UploadWorker: transient I/O/DB/도구 환경 오류는 기존 영속 큐 재시도, 검증 invalid는 고정 코드 FAILED. 24시간 만료는 live lease 대조 후 EXPIRED, exhausted 작업 대조. CANCELLED/FAILED/EXPIRED reserved 해제·slot 반환·작업 권한 철회 한 트랜잭션. COMMITTED 및 기존 자산/used/로컬 원본 미삭제. 예전 lease 효과는 거절.
- 취소 POST /v1/uploads/{id}/cancel 인증·기기·멱등 키·소유권 확인. 반복 동일/새 operation에도 예약 중복 해제 없음. 다른 시도/계정 자료는 조회·취소 불가. COMMITTED 취소는 409.
- 종료 시도 정리는 최소2분 지연·live job 없음·어느 자산에도 final key 연결 없음 대조 후 해당 임시/미확정 키만 객체 I/O 밖에서 반복 가능 삭제. SDK/검증 종료 상한보다 긴 grace, 한 tick 시간 제한 및 별도 scheduler thread로 검증 무한 점유 없음. 늦은 PUT 및 전체 대조는 P12-11.
- 일괄 test bootJar r2CheckerClasspath --offline --console=plain PASS(60초). MySQL 조건부 검사는 실제 CI 후 완료. 검토 보강 관련6 PASS·패키징/검사 classpath PASS(14초). 이후 취소 API 관련2 PASS(11초). 새 스키마나 이전 데이터 초기화 없음.
- 실제 dev.worker 저장 키 audio-check PASS(2026-10-09T00:34:30.663465Z): 임시 객체 삭제 후 최종 바이트 재검증, 불변 객체/중복 정리/존재 없음 확인. 자기 합성 키만 정리, 키 재입력/AI 비밀 조회 없음.
- 현재 모델 별도 검토: 실패 분류·계정/lease 격리·객체 I/O와 DB 분리·reservation1회·COMMITTED 보호·final key/실제 바이트·작업자 재claim 및 오래된 lease 거절·cancel API 영수증 대조. 관련 MySQL checks 연결. USER 행동 없음.
- 최종 커밋 서버·DB CI 확인 후 완료, P12-11 순차 진행.
- 학습: 응답 유실과 프로세스 종료는 성공/실패를 단정할 수 없다. 사전 키와 실제 바이트를 대조하고 원자 상태 전이로 사용량 중복을 막는다.

- 최종 검토 보강: Future 취소의 interrupt를 최종 객체 stream read 반복에서 검사하고 응답을 abort해 늦은 reader 슬롯 점유를 SDK read timeout 뒤에 회수. SDK call/socket 상한과60초 bounded future 함께 적용. 별도 근본 실패 없이 검토 지적 해소.
