# P10-05a — 저장된 스냅샷 페이지 조회 기반

2026-09-30. 원본 P10-05 p00587~589, 설계 p00312/p00773~783, 승인 D09. P10-04 폰 결과와 독립적인 서버 작업이다. D09의 기존 결정을 다시 사용자에게 묻거나 새 Codex 세션에 위임하지 않았다.

## 이번 구현

- SnapshotPageCursor: AES-GCM으로 계정·사본·엔터티·소비한 ordinal·고정 expires_at을 인증한다. sp1 전용 형식/AAD로 일반 목록 커서 p1과 분리한다. 키는 외부에서 주입하고 복사하며 코드에 실제 키를 넣지 않는다. TTL은 재발급 시각이 아니라 사본 header 만료 시각을 따른다.
- SnapshotPages: 계정 인증 후 자기 소유 SYNC/READY 헤더와 저장된 entry만 조회한다. 50/최대100개, ordinal keyset 및 1개 추가 조회로 다음 페이지 유무를 판정한다. 타인/EXPORT는 404, 준비 전409, 만료410. 응답 직전 인증과 헤더 상태를 다시 검사한다. 서버 업무 테이블을 페이지별로 다시 조회하지 않는다.
- SnapshotReadView: 전용 연결의 REPEATABLE READ 읽기 트랜잭션에서 첫 일반 SELECT로 account cursor를 고정하고 같은 연결로 전체 원본 추출을 수행한다. 실패 시 rollback/연결 종료, 새 시도는 전체 읽기뷰부터 다시 시작한다. 반환 전 인증과 생성 10분 제한을 재확인한다. reader는 내부 코드이며 모든 결과를 트랜잭션 안에서 소비하고 남은 timeout을 각 SELECT에 적용해야 한다.
- 현재 모델 별도 코드 검토: V7 엔터티 enum/저장 컬럼, D09의 소유·만료·부분 결과 차단과 대조. SQL 입력은 매개변수화하고 로그 표현에는 payload/token을 노출하지 않는다. TTL 청소 작업과 독립적으로 접근을 차단한다.

## 실제 검증

services/api에서 실행:

```text
gradlew.bat test --tests '*SnapshotPageCursorTests' --tests '*SnapshotPagesTests' --offline --no-daemon
```

실제 결과: **10 테스트, 실패0/오류0/skip0**, BUILD SUCCESSFUL. 커서5 + H2 SQL/인증 회귀5. 변조·다른 키/계정/사본/entity·일반 목록 형식 거절, 재시작 후 같은 키 재개, 정확 만료 경계, 페이지 도중 인증 취소/헤더 만료, EMPTY/limit/재조회 동일성 확인. H2는 MySQL 스냅샷 생성 일관성 검증을 대체하지 않는다.

최초 offline 실행은 H2 2.4.240 캐시 부재로 실패했다. 기존 lockfile 의존성만 다운로드해 단위 테스트5 통과 후 SQL 검증을 추가해 최종10 통과했다. 환경 실패를 제품 수정 실패 횟수로 계산하지 않는다. 로그 .local/workflow/p10-05-pages-test.log; 원본 XML은 build/test-results/test. 운영 DB/볼륨 접근·변경 없음.

현재 모델 직접 구현·검토이며 외부 Worker/Reviewer 없음. 인증/DB 경계에 맞는 높은 추론 목표는 유지하되 실제 모델/추론 자동 변경과 tier를 관측하지 못했으므로 상향 실행으로 기록하지 않는다.

## 미완료 범위

이 코드는 저장된 사본을 읽는 기반이다. Spring Bean/HTTP endpoint는 아직 노출하지 않았다. READ VIEW 생성·용량/슬롯 예약·분할 저장·완결성 검증/READY 게시·복구/청소·OpenAPI·모바일 staging을 완료로 주장하지 않는다. 30분 사본 생성·페이지 사이 관계 일관성 MySQL 검증도 생성 엔진 연결 후 필요하다. 기존 앱 실기 반복 요청 없음. 사용자 확인 대기0건.

이 문서 포함 커밋에서 로컬 검증/현재 모델 검토까지 완료, 정확 SHA CI는 별도 후속 기록. 다음 실제 구현은 D09의 동일 읽기 트랜잭션 기반이다.

## 동일 읽기뷰 추가 검증

위 10 테스트 후 SnapshotReadView 및 MySqlSnapshotReadViewTests를 구현했다. H2 REPEATABLE READ로 교차 테이블 읽기뷰를 검증하려던 최초 시도는 기준 cursor7 뒤 곡 after가 보이는 실패였다. 이를 통과로 바꾸지 않고 동일한 핵심 assertion을 실제 InnoDB 테스트로 옮겼다. H2와 MySQL 격리 의미 차이를 분리하며 해당 핵심 검사를 기존 필수 Idempotency MySQL CI 실행 목록에 추가했다. 기존 테스트는 그대로 유지했다. 테스트 분리 과정의 Connection import 누락은 컴파일 로그 확인 후 보완했다.

실제 MySQL은 기존 격리 개발 서버 127.0.0.1:3307에서 테스트가 만든 고유 p10_snapshot_test_<UUID> 데이터베이스만 사용·정리했다. 원래 개발 DB와 볼륨은 변경하지 않았다. 환경변수 P07_MYSQL_CI=true, P10_MYSQL_PORT=3307; 암호는 로컬 infra/.env에서 메모리로만 읽고 로그/문서에 저장하지 않았다.

실행: `gradlew.bat test --tests '*SnapshotPageCursorTests' --tests '*SnapshotPagesTests' --tests '*SnapshotReadViewTests' --offline --no-daemon`. 최초 **17 통과** 후 deadline 중도 도달 검사를 추가했다. 최종 결과는 아래에 이어 기록한다. 동시 writer commit 이후에도 첫 capture는 cursor7/before, 다음 capture는 cursor8/after를 확인했다. 이 검증은 읽기뷰 기반의 증거이며 전체 엔터티 추출·분할 저장·용량·READY 게시 검증을 대신하지 않는다.

최종: 커서5/페이지5/H2 읽기뷰4/실제 MySQL 읽기뷰5, **19 테스트 통과, 실패0/오류0/skip0**. Python 운영 검사19도 통과. 현재 모델 검토에서 SQL 매개변수·읽기 연결 종료·고정 TTL·재인증·데이터 미노출을 대조했다. 새 커밋의 필수 CI는 아직 확인 전이다.

통합 완료: 7f71d757b9962a77e98e4ad116f5d9caf006a592 일반 push, 필수 CI4 PASS. CI36669212997/API contract36669212978/Idempotency MySQL36669213029/Development workflow36669212995. P10-05a 기반 범위만 완료, P10-05 전체는 진행 중.
