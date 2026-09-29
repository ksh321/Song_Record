# P10-02a 의존 순서와 전송 후보 판정

기준 커밋: P10-01 `2837c381bc81d9a29fbacbe8953eaeccb1db1ca9`.
P10-02를 a: 순서·대기 판정, b: 실제 송신과 응답 반영으로 나눈다.
이번 단계는 네트워크를 호출하거나 ACK를 기록하지 않는다.

## 큐 순서 수정

기존 created_at/op_id 정렬은 같은 밀리초에 저장된 작업의 순서를 UUID에 따라 뒤집을 수 있다.
기기 시계가 뒤로 바뀌어도 잘못된 순서가 생긴다.
현재 v1 local_mutations는 일반 rowid 테이블이므로 rowid를 localOrder로 읽고 그 순서대로 조회한다.
이는 현재 큐 안의 삽입 순서이며 서버 revision이나 전송 식별자가 아니다.
localOrder를 서버/백업 식별자로 보내거나 DB 재구성 후 같은 숫자가 유지된다고 가정하지 않는다.
후속 큐 정리·DB 재구성 구현에서도 미완료 작업의 상대 순서를 보존해야 한다.
새 컬럼·스키마 버전·generated code 변경은 없다.

## 일관된 계획 입력

AccountStore.dispatchSnapshot은 pending 작업과 metadata_copies의 서버 revision/tombstone을
하나의 SQLite 읽기 트랜잭션에서 가져온다. 중간에 다른 로컬 쓰기가 끼어들지 않는다.
기존 AccountStore lease 검증을 사용하므로 다른 계정 DB를 조회하지 않으며 만료 핸들은 거절한다.
Repository.planDispatch는 이 스냅샷을 DependencyPlanner에 전달한다.
반환값은 즉시 계산한 후보 목록이다. 실제 송신 직전에 계정·상태를 재검증해야 하며,
응답을 커밋한 뒤에는 새 계획을 계산해야 한다.

## 판정 규칙

- 같은 대상은 가장 먼저 저장한 미완료 작업 하나만 검사한다. 후속 작업은 earlierMutation 대기다.
- PENDING만 후보가 된다. SENDING/RETRY/CONFLICT/FAILED는 이 단계에서 자동 재실행하지 않는다.
- 삭제 원장 사본/tombstone은 대상 자체와 참조 모두 차단한다.
- PATCH의 baseRevision=0 또는 미확정 서버 기준은 unresolvedBaseline으로 보존한다.
- 현재 서버 사본 revision과 다른 요청은 staleBaseline으로 보존하며 본문/op_id를 변경하지 않는다.
- 참조 대상의 서버 revision이 양수여야 한다. 부모가 ready라는 사실만으로 자식까지 ready로 만들지 않는다.
- 곡의 대표 녹음, 녹음의 곡·태그, 목록 항목의 목록·곡, 녹음 태그 관계의 녹음·태그 참조를 검사한다.
- 명시적 song_id=null은 참조 해제이므로 그 곡을 기다리지 않는다.
- 조건을 만족한 후보는 태그·곡 → 녹음 → 목록·관계 순, 같은 단계에서는 localOrder 순이다.
- 실패한 대상과 무관한 작업은 계속 후보가 된다. 순환 참조는 대기로 남아 무한 탐색하지 않는다.

ready는 의존성과 순서 조건을 만족한다는 뜻이며 API 요청 전체가 유효하다는 뜻은 아니다.
HTTP 경로 지원 여부, 도메인 입력, 인증, baseline 확정 및 재시도 요청 불변성은 송신 계층에서도 검증한다.
기존 로컬 RECORDING_CONDITION과 서버 CONDITION 매핑은 아직 확정하지 않으므로
사용자 UUID 컨디션과 해당 로컬 타입은 unsupported로 보존한다. 기존 기본 컨디션 코드는 허용한다.
파일 작업·서버 전용 사본·삭제/복원 명령도 미지원 단계에서 임의 전송하지 않고 대기 사유를 반환한다.
이 작업들을 없애거나 성공 처리하지 않는다. 조건 매핑과 지원 경로 연결은 실제 송신 전에 완료해야 한다.

## 검증

- dependency_planner_test.dart: 11개 테스트. 선행 실패 격리, 부모 승인 전 대기, DB 순서,
  큐 상태, 미확정/오래된 baseline, 태그·해제, tombstone, 단계 정렬, 미지원 보존,
  잘못된 참조/순환 참조, 불변 계획을 검사한다.
- local_repository_test.dart: 동일 시각·시계 역행·재실행 순서, 계획의 계정 격리 2개 추가.
- 작성 환경에서 실제 v1 SQL로 SQLite 파일을 생성하여 옛 정렬의 역전을 재현하고,
  새 조회의 삽입 순서가 DB 재연결 후 유지되는지 확인했다.
- Flutter SDK가 없어 Dart 분석·Flutter 테스트는 실행하지 못했다.
  적용 스크립트에서 flutter analyze와 전체 flutter test를 실행한다.

다음 P10-02b에서 안전한 요청 확정, 실제 HTTP 송신, 서버 승인 후 원자적 반영을 연결한다.
앱 수동 조작, DB 초기화, 서버 재시작, 앱 재설치는 이번 단계에 필요 없다.

## 2026-09-29 사용자 확인 후 착수 조건

[사용자 확인](../progress.md#user-acceptance-20260929)에 따라 P06 포함 기존 기능은 검증 완료다. P06 기록 부족을 이유로 한 재실기 요구는 제거한다. 컨디션 매핑/송신 계약 정합성은 별도 선행 항목이고, 현재 PC의 Gradle·개발 DB 준비는 별도 실행 환경 과제다. P10-02b를 구현하면 새 송신·응답 반영과 영향 범위를 검증하며 기존 확인으로 새 코드를 통과 처리하지 않는다.
