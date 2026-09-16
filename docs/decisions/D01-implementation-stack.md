# D01 — 구현 기술 결정
- 상태: 확정 (A안)
- 결정일: 2026-09-16
- 승인: 사용자 “A로 가고” 지시
- 담당 작업: P00-04
- 영향 요구사항: R001, R051
- 버전 기준 및 고정 대상: [toolchain-versions.md](../contracts/toolchain-versions.md)

## 결정
Android 앱은 Flutter/Dart, Riverpod, Drift/SQLite, go_router, Dio로 구현한다. 서버는 Java 21, Spring Boot, Spring Data JPA, MySQL 8.4 LTS, Flyway와 Gradle Wrapper를 사용한다. 음성 원격 저장소는 비공개 Cloudflare R2다.

| 영역 | 선택 | 책임 |
|---|---|---|
| 화면 | Flutter/Dart | HTML 배치와 UI_REFERENCE·팔레트 규칙 구현 |
| 상태 | Riverpod | 화면 상태·비동기 상태·의존성 주입 |
| 로컬 저장 | Drift + SQLite | 계정별 메타정보와 미전송 변경 영속 저장 |
| 이동 | go_router | 경로·뒤로가기·로그인 상태에 따른 이동 |
| 통신 | Dio | 인증·취소·오류 변환·서버 API 호출 |
| 서버 | Java 21 + Spring Boot | 인증·소유권·트랜잭션·동기화 계약 |
| DB 접근 | Spring Data JPA | 일반 CRUD와 트랜잭션. 복잡한 조회는 명시적 쿼리로 처리 |
| 서버 DB | MySQL 8.4 LTS | 관계·소유권 제약·revision/change_seq 저장 |
| 스키마 변경 | Flyway | 버전별 마이그레이션 |
| 음성 저장 | 비공개 R2 | 서버 승인 후 제한된 업로드·다운로드 |
| 녹음 | Android 네이티브 연동 어댑터 | 플러그인 제품·버전은 P02 실기 결과로 확정 |

## 선택 이유와 대안
A안은 화면 상태와 로컬 영속 저장의 역할이 분명하며 기존 Flutter·Spring Boot·MySQL 설계와 맞는다. 일반 CRUD에 JPA를 쓰고 로컬 DB와 서버 간 동기화는 별도 Repository/서비스에서 구현한다.

B안의 Bloc은 이벤트·상태 전이가 명시적이지만 초기 작성량이 늘어난다. C안의 MyBatis는 SQL 제어가 편하지만 매핑·CRUD 유지 부담이 늘어난다. 이번 선택은 Riverpod와 JPA이며 Bloc·MyBatis를 기본 의존성에 함께 넣지 않는다.

## 구현 규칙
- 화면은 Riverpod를 통해 Repository를 호출한다. 영속 데이터의 기준은 Drift이며 Riverpod 메모리 상태만으로 기록을 보관하지 않는다.
- 로컬 변경과 전송 대기 기록은 트랜잭션으로 저장한다. 온라인 복귀 후 동기화하며 충돌·삭제·멱등 처리는 기존 설계 및 후속 계약을 따른다.
- 앱은 MySQL에 직접 접속하지 않는다. Dio로 서버 API를 호출한다.
- JPA 엔티티를 API 응답으로 직접 노출하지 않는다. DTO와 소유권 검증을 분리한다.
- 운영 스키마는 Flyway로 변경한다. Hibernate 자동 스키마 변경에 의존하지 않고 검증 모드를 사용한다.
- 녹음 기능은 어댑터 경계 뒤에 둔다. 화면 이탈·백그라운드·중단·복구·저장 성공 여부를 P02에서 확인한다.
- 외부 인기곡 정책은 [D12](D12-popular-periods.md)를 유지한다.

## 검증 범위와 완료 판단
P00-04는 A안 채택, 역할·대안·영향 기록, 공식 SDK/도구 요구 조건 대조, 버전 기준과 고정 대상 목록 작성으로 완료한다. 공식 최소 버전 조건 대조는 전체 의존성 해결이나 빌드 성공을 의미하지 않는다.

현재 저장소에는 앱/서버 프로젝트가 없으므로 실제 lockfile·Wrapper·컨테이너 digest 생성 및 호환 빌드는 P01 프로젝트 생성 시 수행한다. 이번 작업에서 앱 빌드, 서버 실행, DB 마이그레이션, 녹음 실기 테스트를 실행하지 않았다. 원 계획의 “조합을 빌드한 뒤 고정” 순서는 P01에서 유지하며 미실행 검증을 완료로 세지 않는다.

P01에서는 앱 의존성 해결·Drift 코드 생성·분석·Android debug 빌드, Java 21 서버 빌드, MySQL 연결·Flyway 마이그레이션을 확인한다. 실패하면 원인과 수정 버전을 본 결정서/버전 목록에 기록한다. 녹음 플러그인 채택은 P02의 별도 완료 조건이다.
