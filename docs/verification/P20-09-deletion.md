# P20-09 영구 삭제 작업 (원수)

- 원본 계획925~927, 설계559·561·928~930, R098·R099·V22·V30·V42. 요청/관측 6.1 Sol/medium. 현재 모델 직접 구현·별도 검토.
- POST purge는 계정·묶음·선택 대상·base_revision을 검증하고 동일 삭제 당시의 TRASHED 항목만 PURGE_PENDING으로 전환한다. 파일 정책을 울타리로 변경하고 ENTITY_PURGE 작업을 같은 트랜잭션에 저장한 뒤202를 반환한다. 물리 삭제 완료 응답이 아니다.
- 서버 만료 탐색도 같은 준비/작업 경로를 사용한다. 기기 시각은 사용하지 않는다. 복원된 항목·다른 묶음·이미 처리 중 항목을 새로 삭제하지 않는다.
- 작업자는 저장된 계정·묶음 대상과 임대를 검증한다. 소유 최종 키를 기존 CleanupObjects로 HEAD/DELETE/HEAD 확인한 뒤 짧은 DB 확정 트랜잭션에서 원장·양쪽 used 차감·파일 상태 NONE·기록 PURGED를 함께 확정한다. 실패/응답 유실/임대 상실은 확정을 보류하고 기존 JobQueue의 제한 재시도를 사용한다.
- Song-only 삭제의 ACTIVE 보존 녹음은 대상에서 제외한다. Song PURGED 확정 때 그 묶음의 숨긴 목록 항목을 부모 버전·전체 aggregate와 함께 제거하고 entry_key를 해제한다. TJ 예약은 기존 PURGED 생성 열 정책으로 해제하며 삭제 UUID 원장은 남긴다.
- 업로드 완료의 기존 수명/작업/정책 검증과 취소 업로드의120초 안전 유예 정리를 유지한다. 파일 객체 부재 확인은 실제 해당 최종 세대에 대한 확인이며 단순 삭제 명령 성공으로 용량을 줄이지 않는다.
- 기존 worker 역할·storage enabled 설정에서만 처리 스케줄을 연결했다. 이번 작업에서 운영 배포나 기존 사용자 파일의 실제 삭제는 실행하지 않았다.
- 변경: TrashPurge/PurgeWorker/PurgeEvents, 기존 JobQueue·CleanupScheduling·PlaylistService·RevisionChanges, TrashController/Configuration, OpenAPI, H2 및 실제 MySQL 공유 회귀.

## 검사·별도 검토

- gradlew build --offline 전체721개 중639개 실행 PASS,82개 조건부 제외(1분7초). 핵심5개는 물리 실패 후 재시도·한 번 차감·보존 녹음·잘못된 선택/버전·임대 상실·서버 만료를 확인한다. OpenAPI143 경계 PASS, diff 공백 PASS.
- 테스트 준비의 기존 storage_usage 열 중복과 축소 fixture의 recording_asset.created_at 누락을 각각 수정했다. 후자는 DB 확정 예외를 직접 확인하도록 네트워크 준비/DB 효과 경계를 분리해 원인을 확인했다. 별개 준비 원인이며 코드 수정 실패로 합산하지 않는다. 원시 로그는 .local/workflow/p20-09.
- 현재 모델 별도 검토: 엄격 계정/묶음 범위·인증 우선·선택/만료·동일 revision·잠금 정렬·보존 녹음 비연쇄·최종 키/세대/크기/해시·HEAD 확인·임대 fencing·원장 고유키·한 번 차감·목록 부모 revision/aggregate·동기화 tombstone·늦은 업로드 방지·제한 재시도 대조.
- 실제 MySQL·DB 트리거/고유키는 최종 SHA 필수 CI에서 확인한다. R2 인터페이스의 물리 실패는 제어된 객체 대역으로 검증했고 실제 R2 역할/객체 검증의 기존 P13 근거는 유지한다. 이 단계 설치 실기는 해당 없음, P20-10에서 실제 앱 동작 확인.

## 학습 개념

- 영구 삭제 의도, 파일 부재 확인, DB 확정은 서로 다른 시점이다. 파일이 없어졌어도 임대를 잃은 작업자는 용량·상태를 확정하지 못하며 다음 작업자가 부재를 다시 확인해 한 번만 확정한다.
