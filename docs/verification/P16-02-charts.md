# P16-02 — 브랜드·기간별 백그라운드 수집 (원수)

- D12와 R087~R090에 따라 공용 차트 수집을 계정별 JobQueue·동기화와 분리한다. 사용자 조회 요청은 원본을 호출하지 않는다. 운영 저장 이용 조건 미확인으로 실데이터 저장은 차단하고 dev 전용·명시적 fixture-enabled 설정에서만 합성 원본을 수집한다. prod/bootstrap 또는 기본 설정에는 수집 빈이 없다.
- ChartCollection은 TJ/KY×3기간 전체 응답을 2MiB 이내로 수신해 ChartStaging에 넘긴다. 작업 전체 30초 중 원본 20초·저장 트랜잭션 최대10초, 원본 실패 재시도 최대1회, 동시 원본 최대2개. 호출자 제한 시간 이후 도착한 응답은 저장하지 않으며 취소를 무시하는 원본 작업은 실제 종료까지 원본 슬롯을 유지한다. DB 트랜잭션 안 원본 호출 금지.
- V20은 chart_collection_payload에 전체 JSON을 STAGING 스냅샷과 같은 트랜잭션으로 보관한다. 저장 실패는 둘 다 롤백하며 이전 게시 포인터를 건드리지 않는다. scope 잠금으로 revision을 발급한다. 전체 배열 내용 검증과 원자 게시 연결은 순서대로 P16-03/04에서 수행한다. 개발 5분 주기는 공급자 갱신 주기 주장과 무관하다.
- 검사: services/api/gradlew.bat -p services/api test bootJar --console plain. 652개 중 572 성공·80 실제MySQL 로컬 제외·실패0. bootJar PASS. 검토 후 제한 시간 배분 변경은 ChartCollectionTests 7개와 bootJar 영향 검사 PASS. 실제MySQL은 원격 필수 CI에서 확인한다.
- 현재 6.1 Sol/medium 직접 별도 검토: 전체 JSON 복사·동시성·재시도·지연 취소·DB 실패 원자성·실제 prod/dev 설정 게이트 확인. 제한 시간 지적 수정 후 재검증. 새 사용자 조작·폰 실기 필요 없음. 원본 내용 검증/게시가 연결되기 전 수집 fixture는 검증 중 상태로만 저장된다.
- 변경: charts/ChartCollection.java, ChartCollectionConfiguration.java, ChartCollectionScheduling.java, ChartStaging.java, V20__chart_collection_staging_payload.sql, ChartCollectionTests.java. 저장/원자성/작업 제한 학습: 수집 성공과 게시 성공은 별개이며 부분 데이터는 사용자에게 노출하지 않는다.
- 현재 로컬 검사·검토 PASS, 커밋/푸시·정확 SHA 필수 CI 후 완료 판정. 다음 P16-03.

## CI 지적 수정
- 실제MySQL 업그레이드 검사가 신규 V20 추가로 실행 migration 수 10→11이 된 점을 기존 기대값에 반영하지 않아 실패했다. 실행 수11·최종버전20·새 공용 payload 테이블 존재/초기0 확인을 함께 적용하며 기존 사용자 데이터 보존 검사는 유지했다. DB migration 자체 실패가 아니다. 수정 커밋의 필수 CI를 다시 확인한다. 원인 P16-02-MIGRATION-COUNT, 코드 수정 재검증1회.

- 같은 근본 원인 추가 확인: infra/scripts/verify_p04_migrations.sh 최종 Flyway 목록도19까지 고정되어 새20을 거절했다. 전체 관련 검사 검색 후 최종목록1~20으로 보강하며 V4~V9 단계별 목록과 기존 모든 제약 검사는 유지한다. 원인 P16-02-MIGRATION-COUNT 수정 재검증2회, 환경 실패가 아닌 신규 migration 기대값 반영 누락이다.

## 수집 연결 최종 검토 보강
- MananaChartSource의 공식 원본+테스트 loopback만 허용하는 읽기 전용 HTTP 전송을 구현했다. 전체 몸체 크기 제한2MiB·남은 수집 제한 시간·리다이렉트 거절·6개 정확 경로를 실제 loopback HTTP로 검사했다. 운영 빈은 등록하지 않으며 저장 이용 조건 차단은 그대로 유지한다. 전체654개 중574 성공/80MySQL 로컬제외/실패0·bootJar PASS. 현재 모델 최종 diff·오류 분류·운영 gate 재검토 PASS. 앞 CI1504ecb의 이관검사 모두 PASS이나 이 연결 추가 커밋의 필수 CI를 다시 확인한다.

## 최종 완료
- 최종 SHA 7bec51528719de393075dd7b1d89b27a4ce7d572, 필수 CI 38015431945, 38015431978 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
