# P08-09 곡 API 통합 검증

## 범위와 결과 판정

설계서 V31~V33·V42·V46 중 곡 서버 API 책임을 통합 검증한다. 이번 단계는 서버 동작을 새로 추가하는 기능 패치가 아니라 기존 생성·편집·대표 지정·검색·계정 격리의 연결 검증이다. 모바일 오프라인 및 대기 관계 매핑 완료를 의미하지 않는다.

| 검수 | 서버 검증 | 남은 통합 책임 |
|---|---|---|
| V31 같은 TJ 번호, 다른 표기·버전 | 같은 계정은 canonical_song_id 재사용, 편집된 가수·버전 보존 | 앱 canonical ID 적용 |
| V32 같은 곡명·가수, 다른 TJ 번호 | 서로 다른 곡으로 유지, 검색에서도 둘 다 반환 | 녹음 생성·재연결 API와 화면 연결 |
| V33 두 기기의 다른 UUID 등록 | 실제 별도 기기 세션으로 한 canonical ID 매핑, 미채택 UUID 행 없음 | P10-04 대기 녹음·목록 참조와 입력 보존 |
| V42 휴지통·영구 삭제 | P08-08 공통 H2/MySQL 상태/번호/삭제 원장 검사 재실행 | 후속 삭제/복원 API 및 작업자 |
| V46 검색·오프라인·계정 분리 | ACTIVE만 검색, 다른 계정과 휴지통 제외. 기존 SongListingTests의 검색 계약도 재실행 | 앱 로컬 검색·오프라인·동기화 연결 |

## 추가한 HTTP 시나리오

SongApiIntegrationTests는 실제 AccountRegistrationService와 SessionService로 계정 A의 기기 두 개, 계정 B의 기기 한 개를 구성한다. MockMvc를 통해 HTTP 보안 설정·컨트롤러·서비스·테스트 DB까지 실행한다.

1. A 기기 1에서 TJ 곡 생성 → A 기기 2에서 다른 UUID/표기/버전으로 동일 번호 등록 → 기존 곡으로 매핑 → 기기 2에서 제목·메모 수정 → 기기 1에서 대표 녹음 지정 → 기기 2 검색에서 같은 곡 ID·대표 녹음·최신 revision 확인. 옛 생성 요청 재전송은 최초 응답을 유지하며, 오래된 revision 수정은 거절하고 녹음 snapshot은 보존한다.
2. A/B가 같은 번호와 같은 Idempotency-Key로 각각 생성 → 계정별 별도 곡 확인 → A에 같은 제목·가수의 다른 번호를 추가해 자동 병합되지 않음을 확인 → 검색 결과 계정 격리 → B의 A곡 편집·대표 해제 404 → A곡 휴지통 처리 후 A 검색에서만 제외되고 B곡은 유지됨 확인.

녹음 행과 휴지통 상태는 테스트 SQL로 준비한다. 아직 구현하지 않은 녹음 생성·삭제 API를 호출한 것으로 표시하지 않는다. 제목 검색은 서버의 저장된 곡을 조회하며 외부 후보를 합치지 않는다.

## MySQL 검증

MySqlIdempotencyTests에 mysqlSameTjNumberAndOperationKeyRemainAccountScoped를 추가했다. 실제 V2/V6/V10 테이블에서 서로 다른 계정이 같은 선행 0 포함 TJ 번호와 같은 요청 키를 독립적으로 사용할 수 있는지 검사한다. A의 휴지통 예약이 B의 ACTIVE 중복 매핑에 영향을 주지 않는지, 계정별 change_seq와 영수증 수가 맞는지도 확인한다.

MySQL 테스트의 인증은 mock이고, 실제 기기 세션 인증은 HTTP 시나리오에서 검증한다. 기존 MySQL 동시 생성·revision 경쟁·전체 롤백·번호 예약·삭제 원장 검사도 함께 실행하는 구성이다. 제작 환경은 MySQL 전용 테스트를 건너뛰므로 최종 확인은 Idempotency MySQL workflow가 담당한다.

## 변경 및 실행

프로덕션 코드, OpenAPI, 기존 migration은 변경하지 않는다. 테스트 2개와 MySQL 전용 테스트 1개, 이 검증 기록을 추가한다.

- 로컬: services/api에서 gradlew.bat test bootJar.
- 푸시 후: CI / API contract / Idempotency MySQL 모두 성공 확인.
- 신규 환경변수, DB 마이그레이션, 휴대폰 재설치 없음.

다음은 P09-01 녹음 DRAFT 생성 API다. P08의 서버 범위가 통과하더라도 표의 앱·삭제·녹음 후속 책임은 별도 완료 조건으로 남는다.
