# P16-04 — brand·period별 원자 게시 (원수)

- D12·R088~R090: ChartPublication은 동일 scope의 게시 행을 잠그고 전체 원본 검증·항목 배치 저장·스냅샷 PUBLISHED 전환·포인터 교체를 한 트랜잭션으로 수행한다. 실패하면 부분 항목/상태/포인터 전부 롤백하고 이전 동일 브랜드·기간 게시본을 유지한다. 다른 scope로 대체하지 않는다.
- V21은 최신 수집 attempt UUID와 게시 완료 attempt UUID를 별도 보관한다. 실패/진행 중에는 둘이 달라 기존 게시본이 stale임을 조회에서 판단할 수 있다. 가장 나중에 시작한 attempt만 게시 가능해 이전 수집이 늦게 도착해도 새 결과를 덮어쓰지 않는다. 같은 attempt/스냅샷 게시 재실행은 항목 중복 없이 유지한다.
- 기존 공개 스냅샷 포인터가 있으면 두 attempt를 해당 snapshot ID로 초기화해 그대로 보존한다. 신규 요청 시 begin→원본 수집→전체 staging→검증→원자 게시 연결. ChartJobDeadline으로 30초 전체 예산을 시작·staging·게시 트랜잭션이 공유하고 각 DB 단계10초 상한과 남은 예산을 동시에 적용한다. 공급자 저장 허용 전 운영 수집 금지는 그대로 유지한다.
- 로컬 명령 services/api/gradlew.bat -p services/api test bootJar --console plain: 전체667개 중587 성공/80MySQL 로컬제외/실패0·bootJar PASS. 원자 게시6개: 정상/재실행, 빈·손상 대체 거절, 배치 중간 오류 롤백, 실제 두 스레드 역순 게시, scope 혼동/제공자 실패, 공유 예산 만료. 셸 문법 검사도 수행한다.
- 현재 사용자 고정 6.1 Sol/medium 직접 별도 검토: D12·실제 diff·전체 검사·개인 데이터/동기화 제외·기존 게시 보존·경쟁·제한 시간 확인. 실제 MySQL 검사 보강: 기존 V9 업그레이드 CI에 기존 게시본 V21 보존·실제 batch 오류 롤백·두 스레드 늦은 게시 거절·개인 change_log 불변을 연결했다. 로컬 컴파일/bootJar PASS, 실제 DB는 원격 필수 CI에서 확인한다.
- 변경: ChartPublication.java, ChartJobDeadline.java, ChartStaging.java, ChartCollection.java, ChartCollectionConfiguration.java; V21__chart_publication_attempts.sql; ChartPublicationTests.java, ChartMySqlDatabaseChecks.java, ChartDatabaseFixture.java, MySqlIdempotencyTests.java; infra/scripts/verify_p04_migrations.sh. 최종 이관 목록·개수도21/12로 함께 반영해 앞 고정 기대값 문제를 재발시키지 않는다.
- 별도 사용자 행동/폰 실기 없음. 학습: 최신 수집 요청과 마지막 정상 게시를 분리해야 장애 때 원래 차트를 보존하면서 최신 자료로 오인하지 않게 표시할 수 있다.
- 로컬·현재 모델 검토 PASS, 정확 SHA 필수 CI 전 미완료. 다음 P16-05.

## 실제MySQL 지적 수정
- 원인 P16-04-TRIGGER-COMPAT: V7은 신규 차트 STAGING 삽입과 마지막 정상 포인터 보존을 트리거로 강제한다. 이관 시험의 직접 PUBLISHED 삽입을 정상 staging→items→publish 순서로 수정했다. 최초NULL 포인터에서 수집 시도 메타데이터 변경은 기존 트리거가 거절하므로 V22 신규 이관으로 metadata-only begin을 허용하되 scope/정상게시/비회귀 revision/최신 attempt/기존 게시 보존·기존게시 임의 fresh화 금지를 유지했다. V21 등 기존 이관은 재작성하지 않았다. Java에서도 revision 회귀 거절을 명시하고 실제 MySQL의 최초KY 게시·포인터 제거 거절·기존게시 attempt 변경 거절 검사를 추가한다. 최종 이관22/추가13으로 검증 기준 동시 갱신. 분석·수정·재검증1회 진행.

## 사용자 요청 중단 — 2026-10-10T02:34:57.989709+00:00
- HEAD 20faa8f5d0cb4082a859b4a360c335919c564ffe의 실제 MySQL CI 실패 후 P16-04-TRIGGER-COMPAT 수정 1회 보존. V22 신규 이관·최초 staging 시험·revision 회귀 방지·기대 이관22/13 수정은 미커밋 상태.
- 수정 후 전체668개: 588 성공·80 실제 MySQL 로컬 제외·실패0, bootJar PASS. 마지막 SQL 시험문 수정 후 관련 컴파일/bootJar와 셸 문법 PASS. 수정판의 실제 MySQL CI는 아직 미실행이므로 P16-04 미완료.
- 사용자 노트북 종료 요청으로 중단. 다음은 현재 모델 최종 검토 → 명시 파일 커밋·푸시 → 기준 ce7d33a169ca53ab7ec8736e7b7b5b808cebc7bb부터 새 SHA 필수 CI 확인. P16-05~08 미착수. 원수 최초 측정 시작값·오류 시도 이력 유지.
- 코드 백업/해시/재개 순서는 Git 제외 .local/workflow/p16-04/resume.json. 지금 사용자 코드 수정·검사 행동 없음. 다시 켜고 같은 대화에서 재개 요청 필요; 전원 복귀 자동 실행을 보장하지 않는다.

- 중단 최종 확인: 선택기 WAIT(ready/running 없음), 활성 제품·CI 감시 프로세스0, 이전 CI 감시PID17216 종료. USER-062 판본1 폰 알림 서버 접수, 실제 수신 미확인. 사용자 새 재개 요청 전 실행 금지.

- 재개 요청 접수(2026-10-10T03:03:17.278212+00:00): 원수 최초 시작값 유지·실제 새 turn 연결. 저장된 수정 소스 6개 해시 일치. 요청 medium 대비 실제 low 불일치로 USER-063 설정 확인 대기; 제품 추가 수정·커밋·CI 아직 없음.

## 재개 후 최종 검토
- 사용자 중간 설정 회신 후 실제 turn_context gpt-6.1-sol/medium 확인. 기존 수정 소스 해시 동일, 원격 main=20faa8f 확인. 최초 측정 시작값과 원인별 시도1 보존.
- 현재 모델 별도 검토: V7의 STAGING 삽입·PUBLISHED 전체 검증·scope/포인터/revision 보호와 V22 metadata-only begin 구분 대조. 신규NULL 포인터의 begin만 허용하며 기존 게시 제거·게시 attempt 위조·revision 회귀 거절 유지. 기존 이관 파일 재작성 없음. 신규 스코프·경쟁·batch 롤백 검사 연결 확인. 검토 PASS; 실제 MySQL 결과는 수정판 정확 SHA CI 대기.
