# P10-01 로컬 Repository와 변경 큐

기준: P09-08 `1d487b507124a748c411b841501d73807f43af7b`.

## 구현

P04 AccountStore.saveEdit의 SQLite 트랜잭션을 재사용한다. metadata_copies.local_payload와
local_mutations를 함께 저장하고, 큐 삽입 실패 시 로컬 초안도 롤백한다.
LocalRepository는 계정별 AccountStore lease를 받아 준비·저장·조회·미전송 목록 API를 제공한다.
DB를 UI에 노출하거나 별도 큐 DB를 만들지 않는다.

- prepareCreate: 대상 UUID(호출자가 제공하면 보존)와 별도 op_id를 준비한다.
- preparePatch: 대상 UUID, 서버 기준 revision, 전체 로컬 초안, 변경 필드를 준비한다.
- UUID는 Random.secure 기반 v4이고 입력 Map은 LocalEdit 생성 시 canonical JSON으로 고정된다.
- save: 동일 command로 재시도한다. prepare를 다시 호출하면 새 작업이므로 실패 재시도에 사용하지 않는다.
- read: 서버 사본·로컬 초안·서버 revision을 분리해서 반환한다.
- pending: ACKED 외 상태를 포함한다. entity/target/operation도 복원하여 재실행 후 요청 대상을 알 수 있다.

변경 요청의 id·user_id·base_revision 충돌은 준비 단계에서 거절한다.
AccountStore는 저장 시 활성 계정 lease·서버 baseline·tombstone과 op_id 재사용을 다시 검증한다.
같은 command 재시도는 최신 로컬 초안을 옛값으로 덮어쓰지 않는다.
계정 변경·로그아웃 후 오래된 Repository는 조회/저장할 수 없다.

## 예시

```dart
final repository = LocalRepository(activeAccountStore);
final command = repository.prepareCreate(
  entity: LocalEntity.song,
  draft: {'title': '입력 중인 곡'},
  changes: {'title': '입력 중인 곡'},
);
await repository.save(command);
// 결과가 불확실하면 같은 command로 save를 재시도한다.
```

이는 로컬 저장 계층 예시이며 유효한 곡 생성 HTTP 요청의 전체 예시는 아니다.
도메인별 필수값 검증과 HTTP 요청 구성은 해당 기능/송신 계층에서 적용한다.
초안은 전체 로컬 화면 값이며 changes는 변경 의도다. Repository가 필드 단위 병합을 추측하지 않는다.

## 미전송 대상 수정과 후속 단계

baseRevision=0은 서버에 생성되지 않은 로컬 대상이다. 생성 후 오프라인 수정도 별도 작업으로 보존한다.
0을 서버 PATCH에 그대로 전송하면 안 된다. P10-02에서 선행 CREATE 승인과 서버 revision을 확인하고
송신 요청을 확정해야 한다. 이미 전송한 op_id의 본문을 바꿔 재사용하면 안 된다.
현재 pending 목록 순서는 의존 순서 송신 큐가 아니며 정렬 동률은 created_at/op_id다.
네트워크 송신·ACK·재시도·충돌 해소는 P10-02 이후다.

기존 로컬 schema v1과 generated code는 변경하지 않는다. CONDITION 등 서버 분류 타입과 기존 로컬
RECORDING_CONDITION의 명시적 매핑/이전은 송수신을 연결하기 전에 별도로 처리해야 한다.
이번 generic Repository는 기존 LocalEntity 표현을 사용하며 서버 타입으로 자동 해석하지 않는다.
실제 곡·녹음 입력 화면 연결은 후속 기능 단계다. 이번 적용만으로 동기화가 시작되지는 않는다.

## 테스트

local_repository_test.dart의 6개 시나리오:
1. 생성 UUID·op_id·불변 입력과 새 manager 재실행 복구.
2. 미전송 대상 연속 수정 보존, 이전 요청 재시도의 최신 초안 덮어쓰기 방지.
3. 서버 revision=7·base_payload와 PATCH 대상의 재실행 복구.
4. SQLite 큐 삽입 실패 시 초안 롤백과 같은 command 재시도.
5. 계정 A→B 전환 후 데이터 격리 및 오래된 Repository 거절.
6. 잘못된 대상·소유자 입력 및 stale baseline의 무변경 거절.

기존 account_store_test.dart와 함께 flutter analyze / flutter test로 검증한다.
작성 환경에는 Flutter SDK가 없어 Dart 분석·Flutter 테스트는 실행하지 못했다.
적용 스크립트가 사용자 PC에서 전체 분석·테스트를 실행하고 실패하면 중단한다.
GitHub CI는 기존 Flutter 분석·전체 테스트·Android 빌드까지 실행한다.
DB 초기화·서버 재시작·앱 재설치는 필요 없다.
