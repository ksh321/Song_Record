# P13-01 자동 교체 보존 사유 (원수)

- 계획 p00683~685, 설계 p00425~437, R059/V10. P12 단계 완료 후 착수. 요청·관측 모델 gpt-6.1-sol/medium 고정, 현재 대화에서 직접 구현·검사·별도 검토하며 추가 모델 호출 없음.
- RetentionSelectionStore/ReplacementProtection: USER_SYNC→곡→선정 잠금의 짧은 트랜잭션에서 제거되는 기존 STORED 객체에 곡별 PENDING_REPLACEMENT를 저장한다. 현재 대체 대상 전체가 STORED이거나 역할 자체가 해제될 때만 해당 보호 사유를 끝낸다. 관련 작업 ID는 내부 정책의 안정적인 곡 UUID 범위이며 클라이언트 멱등 요청 ID를 재사용하지 않는다.
- 새 대상 실패·미업로드·더 최신 대상 교체 시 기존 보호 유지. 오래된 대체 대상의 업로드 완료만으로 해제하지 않는다. 같은 선정 결과에서도 새 대상 STORED를 재평가하며 정상 무변경은 선정/클라우드 revision을 올리지 않는다. 보호 변경만 기존 asset revision을 올려 이후 정리 확인의 오래된 판정을 막는다.
- RetentionScheduling: 60초마다 100개 계정/곡 보호 묶음을 커서로 순환하며 새 업로드 완료를 재평가한다. 각 묶음은 독립 짧은 트랜잭션, 외부 I/O·파일 삭제·사용량 차감 없음. 업로드 상태를 읽는 모든 판정은 기존 계정 동기화 잠금에 참여한다.
- ReplacementProtectionDatabaseChecks/Tests 및 실제 MySQL 조건부 검사: 최초 보호·중복 방지·현재 대상 교체·오래된 대상 완료·최신 대상 완료·주기 재평가·역할 해제·다른 계정·기존 자산 필드/서버 객체 보존 대조. 실제 파일 삭제나 R2 I/O 변경이 없는 범위이므로 새 폰 실기는 필요 없음. 기존 실기 완료를 재요구하지 않는다.
- 로컬 전체 서버 test/bootJar --offline PASS48초. XML 전체 598, 실패 0, 오류 0, 조건부 건너뜀 74. MySQL 조건부 skip은 통과가 아니며 필수 CI에서 확인한다. 로그 .local/workflow/p13-01/local-final.log, 요약 summary.json.
- 최초 전체 검사 6개 실패 원인 P13-01-H2-HOLD-FIXTURE: 기존 RecordingLinkingTests 공유 H2 스키마에 cloud_hold 누락. 제품 V5 테이블은 이미 존재한다. 테스트 환경을 실제 스키마에 맞춘 수정1회 후 관련4클래스+bootJar PASS10초, 전체 PASS48초. 실패 기대값/제약을 약화하지 않음.
- 별도 현재 모델 코드 검토: 원본의 ‘현재 대체 대상 모두 STORED 또는 역할 해제’ 조건, owner+record+song 범위, 선정 revision, 순차 잠금·트랜잭션 롤백·JobQueue fencing, no-op, 주기 처리의 페이지 진행·기존 자산/used 불변을 실제 diff·결과와 대조. 추가 지적 없음. 서버 DB 동작 변경이므로 서버·MySQL 필수 CI 대기.
- 학습: 선정에서 빠지는 것과 서버 파일을 지울 수 있는 것은 다르다. 새 사본이 안전하게 저장되기 전에는 기존 사본을 별도 사유로 보호한다.
