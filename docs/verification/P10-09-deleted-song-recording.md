# P10-09 — 삭제된 곡의 새 오프라인 녹음 보존

## 요구사항과 범위

원본 계획 p00599~601, 설계 p00306~309: 오래된 수정으로 삭제 대상을 부활시키지 않고, 삭제된 곡을 참조하는 새 오프라인 녹음의 파일·정보를 미연결로 보존하며 재연결을 안내한다. 기존 P09-01의 비활성 곡 409 동작은 **새 DRAFT 생성에 한해** 이 후속 요구사항으로 보완한다. 기존 녹음의 연결 변경은 계속 소유권/ACTIVE 조건을 요구한다.

현재 모델이 직접 구현·검토했다. 별도 Worker/Reviewer 위임 없음. 서버 계정 격리·삭제·멱등 범위여서 높은 추론이 필요한 작업으로 판단했지만 실행 모델/속도를 변경했다고 주장하지 않는다.

## 구현

- `RecordingDrafts.availableSong`: 인증 계정의 SONG 삭제 원장 또는 TRASHED/PURGE_PENDING/PURGED 상태가 확인된 경우에만 새 녹음의 song_id를 null로 저장한다. 알 수 없거나 다른 계정의 ID는 기존 404다. 같은 UUID의 기존 녹음을 수정하거나 Song을 재생성하지 않는다.
- 원래 요청 본문/op_id/멱등 해시는 유지한다. USER_SYNC 잠금과 READ_COMMITTED 경계 안에서 확인하고 녹음·change_log·영수증을 함께 커밋한다. 추가 역순 Song 잠금이나 스키마 변경 없음.
- `dependency_planner.dart`: 본인 계정 사본에 삭제 표식이 있어도 유효한 새 RECORDING CREATE/DRAFT만 원본 그대로 서버에 보낸다. 이미 삭제된 녹음 자체, 기존 녹음 PATCH, 미확인 선행 대상, 다른 관계의 삭제는 계속 차단한다. 서버가 최종 소유권/삭제 상태를 확인한다.
- `AccountStore.unlinkedOfflineRecordingCount`와 RepositorySyncBackend: 원래 요청에는 곡이 있었으나 ACK 응답과 현재 서버 사본은 미연결인 녹음 수를 읽어 재연결 안내를 표시한다. 일반적인 미연결 녹음 전체를 경고로 추정하지 않는다. 재연결/삭제 후에는 안내 대상에서 빠지며 기존 요청 이력은 유지한다.
- OpenAPI 설명에 이 동작과 404 경계를 반영했다. API 필드 형태 변경 없음.

## 검증

| 실제 실행 | 결과 |
|---|---|
| Gradle RecordingDraftTests, RecordingLinkingTests | 13 PASS, 실패/skip 0 |
| flutter test --no-pub test/dependency_planner_test.dart test/recording_link_dispatch_test.dart --reporter expanded | 18 PASS |
| flutter test --no-pub test/deleted_song_recording_test.dart test/sync_controller_test.dart test/change_feed_sync_backend_test.dart test/snapshot_sync_backend_test.dart --reporter expanded | 보완 후 50 PASS |
| flutter analyze --no-pub 변경 Dart 6파일 | No issues found |
| infra/scripts/verify_api_contract.py | OpenAPI/참조/보안/7 wire/141 경계 PASS |
| 새 MySQL 회귀 메서드 포함 Gradle 실행 | 컴파일 성공, 해당 메서드 1 SKIP: P07_MYSQL_CI 미설정. 실제 MySQL 통과로 기록하지 않음 |

클라이언트가 삭제를 이미 알거나 모르는 두 경우 모두 같은 녹음 UUID·원본 op_id·요청 본문·고정 wire·파일 DB 행·합성 파일 바이트가 보존됨을 검사했다. 안내는 DB 재개방 후에도 남고 현재 서버 사본의 연결이 바뀌면 사라진다. 서버는 세 삭제 상태·본인/타인/다른 종류의 원장·미확인 ID·동일 op_id 재전송·다른 본문 충돌·기존 녹음 연결 거절·로그 실패 롤백을 검사했다.

초기 통합 테스트는 실제 컬럼 body_json을 body로 읽은 테스트 오류와 예외 시 raw DB 정리 누락 때문에 실패했다. 실제 컬럼과 finally 정리를 수정했고 검사 조건을 삭제/약화하지 않았다. 환경 실행 실패는 별도다: 기본 Gradle 소켓 경로에서 기존 루프백 오류를 다시 관측했으나, 기존 ENV-GRADLE-LOOPBACK 문서의 프로세스 한정 JAVA_TOOL_OPTIONS 보정으로 서버 테스트가 성공했다. 전역 설정·DB/볼륨 데이터는 바꾸지 않았다.

로그: `.local/workflow/p10-09-api-shortdir.log`, `p10-09-api-reviewed.log`, `p10-09-planner.log`, `p10-09-mobile-reviewed.log`. MySQL 검증은 새 메서드 `mysqlDeletedSongDraftPreservesIdentityAndNeverRecreatesParent`를 필수 CI에서 실행한다. 로컬 기존 개발 DB 포트와 검증 컨테이너 포트가 달라 잘못된 DB에 테스트를 실행하지 않았다.

## 남은 검증

커밋 후 정확 SHA의 필수 CI/MySQL 결과를 확인한다. 신규 UI 휴대폰 실기는 실행하지 않았다. 이 변경은 현재 지원되는 새 DRAFT 전송 경로이며, 전체 녹음 저장·파일/관계 송신의 잔여 구현이나 전체 P10 완료를 의미하지 않는다. 기존 USER-025 확인을 새 변경에 확대하지 않는다. 다음은 오래된 수정의 삭제 표식·잔여 송신/수신 통합 범위를 대조하고 필요한 실기만 정확한 버전과 절차로 준비하는 것이다.

최종 현재 모델 검토: 원본 ‘재연결 안내’가 빈 큐에서 숨지 않는지 widget 회귀 검사를 추가했다. 안내 표시와 연결 해소 후 빈 상태로 전환을 확인했다. 6개 관련 Flutter 테스트 파일을 함께 실행한 최종 결과 **69 PASS**(`p10-09-mobile-final.log`). 앞 18/50과 중복된 범위를 포함하므로 단순 합산하여 고유 테스트 수를 주장하지 않는다. 새 MySQL 메서드는 실제 V2/V6 제약하의 3개 삭제 상태 및 원장만 남은 곡에 대해 UUID/정보/로그/영수증 보존과 부모 미재생성을 검사하며 필수 CI에서 실제 실행 예정이다.

구현 커밋: f608be1c1e1425a11af8f64a229a7c26bb6ec781 일반 푸시 완료. 진행 중 목록 규칙35dbbaf도 함께 원격 보존했다. 정확 SHA 필수 CI/MySQL 확인 중이며 아직 전체 완료 판정하지 않는다. 공식 사용량97%/ordinaryUsageAllowed=true를 확인했고 리셋권은 사용하지 않았다. 현재 실행 중인 로컬 테스트 프로세스는 모두 종료했다. 다음 재개는 이 SHA CI 확인 및 P10-02의 기존 RecordingSaving API 대비 누락된 SAVED/파일 명세 전송 경로 분석이다. 기존 원본 계획의 파일 업로드와 메타정보 전송을 혼동하지 않는다.

2026-10-01 후속 실제 확인: f608be1c1e1425a11af8f64a229a7c26bb6ec781의 CI/API contract/Idempotency MySQL/Development workflow 모두 PASS. 실행 ID 36831205718/36831205710/36831205659/36831205700. 앞의 CI 대기 문구는 관측 당시 상태다. 새 실기/전체 P10-09 완료로 확대하지 않는다.
