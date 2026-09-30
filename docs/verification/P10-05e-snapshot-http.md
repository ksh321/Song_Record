# P10-05e — 만료 정리·상태/페이지 API·서버 실행 연결

2026-09-30. 요구사항 P10-05/D09, S03~S05/S10/S11/S14. 현재 작업 모델 직접 구현 후 별도 코드 검토 단계 수행. 새 에이전트 없음. 요청 모델은 동기화·계정 격리 작업에 Astra/high 이상이며 실제 모델/추론 변경·Standard tier는 독립 관측 불가로 미확인 유지.

## 변경과 보존

- SnapshotCleanup: 5분 주기의 파생 사본 정리. 만료 READY, FAILED/EXPIRED, 실행할 durable job이 없는 만료 BUILDING, DELETING 계정 사본을 처리한다. capacity→header→job 순서로 잠금, V7 trigger로 예약 바이트 환급. 재시도할 job이 남은 BUILDING은 worker가 부분 행을 폐기하고 새 읽기뷰에서 재생성한다. 원본 업무 행과 mutation_receipt를 삭제하지 않는다.
- SnapshotQueries/Controller: POST /v1/sync/snapshots 접수, GET /v1/sync/snapshots/{token} 상태/엔터티 페이지. 상태 조회 BUILDING202/READY200, 페이지 준비 전409, 만료410, 타인/미발급 토큰404. 정리된 자기 토큰은 기존 receipt로410 판정. 알 수 없는/중복 query, 잘못된 token/limit/cursor 거절. READY 메타정보와 19종 개수, canonical manifest 해시 제공. 페이지 payload는 JSON 객체이며 성공 응답 no-store.
- SnapshotConfiguration: 기존 AccountAccess/멱등 경계를 사용한다. HTTP 보안은 필요한 POST/GET만 허용하고 서비스가 Bearer/device를 인증·재확인한다. 다른 메서드/하위 경로는 차단. 일반 JobQueue2분 설정은 보존하고 생성 worker만10분 lease를 사용한다. 기존 pagination32바이트 키를 별도 AAD의 snapshot cursor에 사용해 재시작 후 재개한다.
- SnapshotScheduling: 기본 활성, snapshot 전용2개 thread(생성 하나/정리 하나), 생성 tick1초·정리5분. 작업 lease와 READY는 DB 영속. bootstrap에서는 비활성. 테스트만 songrecord.snapshots.scheduling-enabled=false로 예약 등록을 끌 수 있으며 제품 API 검증/CI는 그대로 유지. tick 오류는 예외 종류만 기록하고 개인 payload·SQL 상세를 출력하지 않는다.
- OpenAPI 및 wire 경계 사례9개 추가. 기존 사례125개 유지.

## 실행 검증

```text
gradlew.bat test --tests '*MySqlSnapshotSourceRowsTests' --offline --no-daemon
gradlew.bat test --tests '*SnapshotHttpTests' --tests '*SnapshotSchedulingTests' --offline --no-daemon
gradlew.bat test --tests '*Snapshot*Tests' --offline --no-daemon
.local/contract-venv/Scripts/python.exe infra/scripts/verify_api_contract.py
```

- 최초 실제 MySQL source11 통과: 상태202→READY200→페이지, 중복 query 거절, 만료 접근 차단, 정리 후 원본 곡/receipt 보존·동일 op replay, 파생 행 제거·capacity 합계 일치, 타인404, durable job 보존·orphan/탈퇴 정리.
- HTTP 최초5 중2 실패는 Spring이 mock JdbcTemplate.afterPropertiesSet을 호출한 초기화 이력을 요청의 DB 접근으로 센 fixture 오류다. 초기화 직후 invocation만 비우고 동일 요청 DB 무접근 assertion을 유지했다. 제품 보안 assertion을 삭제/완화하지 않았다. 이 문제 수정1회 후 아래 통합 통과.
- 최종 snapshot **45 통과, 실패0/오류0/skip0**: 실제 MySQL26, H2/커서14, HTTP3, 예약 실행2. 인증 실패 시 DB 접근 없음, 다른 메서드403, 무쿠키/무세션202/no-store, 설정 Bean 연결, 생성/정리 예약2개 등록·bootstrap 제외, 오류 후 다음 tick 실행 확인.
- 계약 검증: OpenAPI/local refs/security/wire7/경계134 통과. 로그 .local/workflow/p10-05-cleanup-test.log, p10-05-http-test.log, p10-05-http-integration.log. 명령별 실제 결과를 구분하며 최초 실패를 최종 통과로 덮어쓰지 않는다.
- DB는3307의 테스트가 만든 p10_*_test_<UUID>만 정리했다. 기존 개발 DB/볼륨/폰 앱/로그인 설정 보존. 이번 서버 변경의 폰 실기를 실행했다고 기록하지 않는다.

## 현재 모델 코드 검토와 다음

D09 원본, V7 trigger/FK, 실제 diff, HTTP 보안 경로, account revalidation, lease/cleanup 경쟁, 원본 보존과 실제 결과를 대조했다. READY는 불변이고 조회 전후 재확인하며 부분 사본을 노출하지 않는다. cleanup은 capacity를 먼저 잠가 builder와 예약 환급을 직렬화한다. 현재 모델 검토이며 독립 에이전트 검수 아님.

서버 기반 연결의 로컬 검증 완료; 커밋/정확 SHA 필수 CI는 후속 기록으로 확정한다. 기존 실행 중인 개발 API는 이전 빌드이며 이번 코드를 재시작 배포한 것으로 보지 않는다. 다음은 모바일 응답 검증·영속 staging·manifest 완결성 검증·미전송/파일 보존 원자 적용. 전체 P10-05는 아직 완료가 아니다. 사용자 확인 대기0건.
