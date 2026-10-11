# P19-04 후보와 등록곡 연결

- 사용자 승인: P19-09까지 원수 순차 실행. 요청/관측 모델 gpt-6.1-sol/medium, 현재 모델이 구현·검사 후 별도 검토를 수행했다.
- 기준 커밋: d4e12d824d2601f6c7031dc0accddbfefcda580e. 최초 시작 사용량은 기존 원수 begin 훅으로 저장했으며 이전 완료 측정과 중복하지 않았다.
- 원본 계획서 v1.0 Word 문단878~880, 설계서 v1.11 문단681~683·831~832 직접 확인. 해시는 P19-03 기록의 보존 원본과 동일. 요구사항 R080·R082, 기존 소유 계정·활성 곡·변경 로그·불변 재시도 계약을 적용했다.

## 구현과 검토

- 새 TJ Song 생성 트랜잭션 안에서 동일 계정·번호의 미등록 후보를 연결한다. 삭제한 부모, 다른 계정·번호 및 이미 연결된 항목은 유지한다. 부모를 ID 순서로 잠그고 RevisionChanges로 버전을 증가시키며 전체 항목 집합을 변경 로그에 기록한다. ID·position·entry_key·후보 출처는 변경하지 않는다.
- PATCH /playlists/{id}/items/{itemId}/song은 같은 계정 ACTIVE TJ와 후보 번호가 같을 때만 연결한다. 다른 번호·MANUAL은 VALIDATION_FAILED, 타 계정/없는 항목은 404, 오래된 부모 버전은 409. 같은 곡 재연결은 changed false·버전 불변. 불변 영수증 재전송은 원래 결과를 반환한다.
- 앱의 준비 명령·실제 경로·전체 응답 적용·불변 재시도를 연결했다. 응답의 항목 ID·연결 곡·후보 원본·순서·계정·부모 버전을 확인하고 늦은 응답은 새 수신 결과나 삭제된 부모를 되살리지 않는다.
- 변경 파일: PlaylistService/Controller/Configuration, SongCreation/Configuration, 서버 PlaylistTests·SongCreationTests·KaraokeRegistrationTests·MySqlIdempotencyTests, 앱 MutationRequest·playlist_addition_receipt·AccountStore·RetryControls·PlaylistLibrary, 격리 fixture·playlist_addition_test, OpenAPI.
- 현재 모델의 별도 검토: 원본 자동 연결 완료 기준, 계정/번호 제한, 잠금 순서, DB 원자성·전체 롤백, 항목과 출처 보존, 중복 응답, 실패 큐 보존, 늦은 응답/불변 재전송을 diff와 검사 결과에 대조했다. 미해결 지적 없음.

## 실제 로컬 검사

- `.local/workflow/p19-04/checks.ps1` 서버 build PASS. 모바일 전체는 969개 PASS·신규 결합 시나리오1개 FAIL. 거절 요청이 FAILED 선두로 남아 뒤 성공 요청을 막는 기존 계약을 테스트가 고려하지 않은 원인이다(P19-04-TEST-QUEUE-01). 제품 큐 규칙을 변경하거나 실패 요청을 삭제하지 않았다.
- 기존 테스트 문장/단언을 모두 보존하고 각 거절 반복에 별도 격리 DB를 추가해 실제 PATCH 전송·FAILED 보존 단언을 보완했다. 모바일 영향5개 PASS: 다른 번호/MANUAL 거절, 동일 ID·순서·후보 출처, 응답 유실·불변 재전송, 같은 곡 재연결, 재시작 및 기존 추가 회귀. 전체의 다른969개 통과와 영향 결과를 합쳐 확인했으며 전체 재실행으로 표기하지 않는다.
- 서버 후속 영향 검사 PASS, 최종 PlaylistTests 10개 PASS: 여러 부모·다른 번호·삭제 부모·다른 계정 보존, 명시 연결·동일 연결·멱등 재전송, 버전 한도 오류 시 Song·출처·후보·영수증·로그 전체 롤백.
- `.local/workflow/p19-04/remaining-checks.ps1`: analyze 0, OpenAPI/wire7·경계141 PASS, 기존 격리 APK build PASS, diff 검사 PASS. 최초 분석의 중괄호5건은 보완 후 재검증했다. 로그는 Git 제외 경로에 보존.
- 실제 MySQL JSON·동일성 UPDATE 트리거·자동 연결 변경 로그·동일 곡 재연결 검사를 필수 CI에 보완했다. 로컬의 CI 전용 건너뜀을 통과로 계산하지 않는다.
- 새 화면/사용자 조작을 추가하지 않는 서버·큐 경계 작업이다. P19-02 설치본 근거를 보존하며 실제 후보 검색·복귀 화면 검사는 원본 P19-07에서 진행한다.

## 커밋·CI

- 위 로컬 검사·현재 모델 검토 승인. 대상 SHA의 필요한 CI를 확인한 후에만 최종 완료를 기록한다. 다음 P19-05는 그 이후 시작한다.
