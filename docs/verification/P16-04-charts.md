# P16-04 — brand·period별 원자 게시 (원수)

- D12·R088~R090: ChartPublication은 동일 scope의 게시 행을 잠그고 전체 원본 검증·항목 배치 저장·스냅샷 PUBLISHED 전환·포인터 교체를 한 트랜잭션으로 수행한다. 실패하면 부분 항목/상태/포인터 전부 롤백하고 이전 동일 브랜드·기간 게시본을 유지한다. 다른 scope로 대체하지 않는다.
- V21은 최신 수집 attempt UUID와 게시 완료 attempt UUID를 별도 보관한다. 실패/진행 중에는 둘이 달라 기존 게시본이 stale임을 조회에서 판단할 수 있다. 가장 나중에 시작한 attempt만 게시 가능해 이전 수집이 늦게 도착해도 새 결과를 덮어쓰지 않는다. 같은 attempt/스냅샷 게시 재실행은 항목 중복 없이 유지한다.
- 기존 공개 스냅샷 포인터가 있으면 두 attempt를 해당 snapshot ID로 초기화해 그대로 보존한다. 신규 요청 시 begin→원본 수집→전체 staging→검증→원자 게시 연결. ChartJobDeadline으로 30초 전체 예산을 시작·staging·게시 트랜잭션이 공유하고 각 DB 단계10초 상한과 남은 예산을 동시에 적용한다. 공급자 저장 허용 전 운영 수집 금지는 그대로 유지한다.
- 로컬 명령 services/api/gradlew.bat -p services/api test bootJar --console plain: 전체667개 중587 성공/80MySQL 로컬제외/실패0·bootJar PASS. 원자 게시6개: 정상/재실행, 빈·손상 대체 거절, 배치 중간 오류 롤백, 실제 두 스레드 역순 게시, scope 혼동/제공자 실패, 공유 예산 만료. 셸 문법 검사도 수행한다.
- 현재 사용자 고정 6.1 Sol/medium 직접 별도 검토: D12·실제 diff·전체 검사·개인 데이터/동기화 제외·기존 게시 보존·경쟁·제한 시간 확인. 실제 MySQL 검사 보강: 기존 V9 업그레이드 CI에 기존 게시본 V21 보존·실제 batch 오류 롤백·두 스레드 늦은 게시 거절·개인 change_log 불변을 연결했다. 로컬 컴파일/bootJar PASS, 실제 DB는 원격 필수 CI에서 확인한다.
- 변경: ChartPublication.java, ChartJobDeadline.java, ChartStaging.java, ChartCollection.java, ChartCollectionConfiguration.java; V21__chart_publication_attempts.sql; ChartPublicationTests.java, ChartMySqlDatabaseChecks.java, ChartDatabaseFixture.java, MySqlIdempotencyTests.java; infra/scripts/verify_p04_migrations.sh. 최종 이관 목록·개수도21/12로 함께 반영해 앞 고정 기대값 문제를 재발시키지 않는다.
- 별도 사용자 행동/폰 실기 없음. 학습: 최신 수집 요청과 마지막 정상 게시를 분리해야 장애 때 원래 차트를 보존하면서 최신 자료로 오인하지 않게 표시할 수 있다.
- 로컬·현재 모델 검토 PASS, 정확 SHA 필수 CI 전 미완료. 다음 P16-05.
