# P07-04 revision 기반 변경

## 개념

revision은 자료의 서버 버전 번호, base_revision은 앱이 수정의 기준으로 삼은 버전 번호다.
두 기기가 버전 1을 보고 수정할 때 먼저 성공한 변경은 버전 2가 된다. 나중에 도착한 base_revision=1 요청은 최신 내용과 버전 2를 포함하는 409 REVISION_CONFLICT로 거절한다.
요청 키는 재시도를 구분하고, 버전 번호는 오래된 내용을 기준으로 한 수정을 구분한다.

## 구현

RevisionChanges는 SONG, RECORDING, PLAYLIST, TAG의 계정별 행을 SELECT ... FOR UPDATE로 잠근 뒤 버전을 비교한다.
API 수준에서는 버전을 제출하는 낙관적 충돌 검사를 사용하고, DB에서는 검사·변경 사이의 경쟁을 막기 위해 행 잠금을 유지한다.

- 인증된 계정의 user_id와 자료 id를 함께 조회한다. 타인/없는/잘못된 ID는 최신 값을 노출하지 않고 404다.
- base_revision은 필수 양의 정수다. 현재보다 작은 값뿐 아니라 미래 버전도 충돌이다.
- 일치하면 업무 콜백을 실행한 후 revision을 정확히 1 올리고 updated_at을 UTC로 갱신한다.
- UPDATE에도 user_id, id, 기존 revision 조건을 유지한다. 콜백이 ID/소유자/revision을 바꾸거나 행을 삭제하면 전체 트랜잭션을 실패시킨다.
- 불일치면 details.current_revision과 details.current를 가진 기존 오류 봉투를 반환한다.
- current는 명시한 메타데이터 필드만 포함한다. 소유자 ID, 자산 경로/서명 URL, 인증 토큰, 내부 정규화 키는 포함하지 않는다. null은 유지한다.
- Long.MAX_VALUE에서는 증가를 거절한다.

기존 P07-03 트랜잭션 안에서 호출해야 한다. 트랜잭션 없이 호출하면 거절한다. 업무 변경, 버전 증가, 멱등 결과 기록은 같은 트랜잭션으로 커밋/롤백된다.
멱등 결과를 먼저 확인하므로 성공한 요청의 재시도는 현재 버전이 더 올라갔어도 원래 결과를 반환한다. 새 요청 키로 과거 버전을 수정하면 REVISION_CONFLICT다.

## 후속 API 연결 규칙

```java
var reply = mutations.execute(account, key, "PATCH", targetPath, requestBody, () -> {
    var current = revisions.change(account, Resource.PLAYLIST, playlistId, baseRevision, before -> {
        // 입력 검증/삭제 상태/관계 소유권 확인 후 같은 DB에서 변경한다.
        // SQL에도 반드시 인증된 user_id와 자료 id 조건을 넣는다.
        // revision, updated_at은 공통 코드가 변경한다.
    });
    return new Reply(200, json.writeValueAsString(current));
});
```

- requestBody의 base_revision과 실제 비교 인자는 동일한 파싱 결과를 사용한다.
- 프런트에서 충돌을 받았다고 최신 revision만 대입해 자동 덮어쓰지 않는다. 최신 값과 사용자 변경을 비교/확인한 뒤 새 작업 키로 수정한다.
- 재생목록 항목 추가/삭제/정렬은 Playlist 행의 버전을 사용한다. 항목 자체에 가상의 revision을 만들지 않는다. current는 부모 메타데이터이므로 필요한 최신 항목 목록은 별도 조회한다.
- Recording 관계 변경의 link_revision 규칙은 도메인 서비스에서 별도로 적용한다.
- 이 코드는 lifecycle 변경 가능 여부, 필드별 PATCH 의미, 도메인 유효성 검사를 대신하지 않는다. 최신 값 응답은 공통 메타데이터 투영이며 전체 도메인/관계 목록 응답이 아니다.
- 도메인 잠금이 추가되면 설계서의 전역→계정 동기화→권한·용량→선정·슬롯→파일 순서를 지킨다. P07-05의 change_seq/ChangeLog는 아직 구현하지 않았다.
- 외부 네트워크/파일 작업을 잠금 안에서 수행하거나 콜백에 REQUIRES_NEW를 사용하지 않는다.

업무 API/모바일 충돌 화면은 후속 단계에서 연결한다. 테스트용 HTTP 경로만 추가했으며 운영 보안 허용 경로를 넓히지 않는다. SQL 마이그레이션/앱 재설치가 필요하지 않다.

## 검증

H2에서 4종 자료의 버전 증가, 최신 상태 반환, 과거/미래/누락/0 버전, 타인 자료 비노출, 세션 폐기, callback 실패 롤백, 중복 버전 증가 방지, 동시 수정, P07-03 결과 재사용, HTTP 오류 계약을 검증한다.
기존 MySqlIdempotencyTests에 V4 실제 Playlist DDL을 사용하는 경쟁 수정/충돌/멱등 재시도 검사를 추가한다. 기존 Idempotency MySQL workflow에서 자동 실행하므로 새 워크플로는 추가하지 않는다.
작업 환경에는 Docker가 없어 MySQL 전용 3개는 로컬에서 건너뛰며 CI 결과 확인이 필요하다.
Windows 적용 스크립트는 test bootJar를 실행한다. 이후 CI, API contract, Idempotency MySQL 세 가지가 모두 성공해야 다음 단계로 진행한다.

## 직접 설명해 볼 질문

1. 요청 키가 다르지만 base_revision이 같은 수정 두 개가 동시에 오면?
2. 성공 응답을 못 받아 같은 키/같은 본문으로 다시 보내면?
3. 충돌 때 받은 최신 revision만 자동으로 넣어 재전송하면 왜 위험한가?

1번은 한 요청만 성공하고 다른 요청은 충돌한다. 2번은 원래 결과를 재사용한다. 3번은 사용자가 보지 못한 다른 기기의 변경을 덮어쓸 수 있기 때문이다.
