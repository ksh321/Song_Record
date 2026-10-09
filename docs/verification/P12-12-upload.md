# P12-12 업로드 실패 검증 (원수)

- 원본 계획 p00675~677, 설계 V07·V14~V16, R066~073/R118/R119/R122. 앞선 P12-11 최종 필수 CI PASS 후 finish→begin, gpt-6.1-sol/medium 요청·관측. 같은 대화에서 구현·검사·별도 검토, 추가 모델 호출 없음.
- UploadFailureDatabaseChecks/Tests: 기존 STORED 파일을 둔 상태에서 검증 후 보관 대상 해제, 곡 삭제, 임시 파일 부재, 취소, 실제 체크섬 불일치, 정책 변경, 같은 녹음의 기존 세대 존재를 검증한다. 실패한 새 시도만 예약 해제하고 기존 자산 전체 필드·사용량·바이트를 유지한다. 실패/취소 반복과 고아 정리 뒤에도 기존 키 삭제 호출 없음, 실패한 시도의 자산 변경 로그 없음 확인. 실제 MySQL 일회용 DB 테스트에도 같은 시나리오 연결.
- DevelopmentAudioProbe/R2CredentialCheck/R2Storage 개발 진단: 서명 URL을 한 번만 만들고 동일 URL로 정상 합성 오디오 PUT→실제 바이트 검증→손상 바이트 PUT→검증된 캡처를 최종 객체로 생성→같은 URL로 다시 PUT. 최종 원본 유지·다른 바이트 덮어쓰기 거절·임시 삭제 후 최종 복구·자기 합성 객체 정리까지 실제 R2 확인. 키·URL 메모리 사용, 로그/보고서에는 고정 결과만 기록. dev/worker 제한과 임시 키 타입 경계 유지.
- 한 명령 .local/workflow/p12-12/check-local.ps1: 서버 test/bootJar/classpath PASS48초, XML596개 중 실행523·조건부73, 실패0·오류0. 앱 업로드 큐/전송 검사4개 PASS3초. 최종 로그 final-server.log/final-mobile.log, XML summary.json. 실제 MySQL 조건부 건너뜀은 통과 실적이 아니며 CI 대기.
- 실제 dev.worker audio-check PASS UTC2026-10-09T01:36:01.338483+00:00, audio.temporary VERIFIED. 기존 저장 키 자동 사용, 재입력 없음. 실제 개발 R2 자기 시험 키만 생성·정리. 임시 URL 재사용은 worker 자격의 개발 진단 signer로 수행했으며 앱/API 최종 쓰기 권한을 추가하지 않았다.
- V07: 기존 P09-08 metadata-boundary 검사(QUOTA/PIN_LIMIT/BUDGET에서 DRAFT·SAVED·수정·티어·연결 및 정보 변경 로그 성공)를 이번 서버 전체 검사에 포함. V14: 기존 개인/전체 경계 동시 승인·롤백 검사 포함. V15: 기존 finalization/recovery/complete 멱등·lease 검사 포함. V16: native 오디오/자원 상한 검사와 위 실제 R2 동일 URL 재사용 확인.
- 앱 원본: 기존 upload_queue의7개 시나리오(정보 승인 전 미전송·순서·네트워크 실패·취소·인증 만료·계정 전환·PUT만으로 STORED 금지)에서 실제 임시 테스트 디렉터리 원본 바이트·정보를 검사하고 재실행 보존 확인. 기존 P12-05 폰 실기7개 통과 근거 보존. 이번에 앱 코드 변경이나 새로운 폰 실기를 요구하지 않는다. 서버 DB 모의 바이트 검사를 실제 폰 검사라고 부르지 않는다.
- 별도 현재 모델 검토: 완료 기준·실제 diff·검사 결과·기존 세대 보호·사용량1회 해제·외부 I/O와 트랜잭션 경계·계정/lease·키 권한·검증 테스트 기대 대조. 같은 녹음 기존 세대 사례 추가, 실제 MySQL의 곡 TRASHED에 deleted_at 포함하여 제약 유지. 이후 영향 범위 검사로 재확인.
- 준비 오류: 체크 함수명과 Mockito verify 충돌, 바이트 source의 checked exception 계약을 컴파일 때 수정(서로 다른 원인). H2 job check가 생성 연결 종료 후 invalid가 된 fixture는 기존 테스트와 같은 생성 연결 유지로 수정1회 후 PASS. 제품 제약 삭제/완화 없음.
- 현재 커밋·푸시·필수 CI 전. 최종 SHA CI PASS 뒤 P12 전체 완료·원수 측정 마감·승인 범위 종료 알림. P13 미승인.
- 학습: 새 업로드 실패는 이미 안전하게 보관한 세대와 로컬 원본의 삭제 이유가 아니다. 예약·미확정 객체의 정리와 기존 파일 보존을 서로 다른 경계로 검증한다.
