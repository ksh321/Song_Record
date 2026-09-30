# P10-04b-CONNECT — 송신 응답과 원자 매핑 연결

2026-09-30. 요구사항: 계획 P10-04 p00584~586, 설계 p00293. 원본 대응은 reference/search/manifest.json. 선행 ATOMIC/GATE/EXPORT 구현·검증 완료, EXPORT bf2ce11 필수 CI4 PASS. 새 Worker/Reviewer 호출 없이 현재 작업 모델이 구현 및 별도 코드 검토 단계를 수행했다.

## 변경과 검토

- metadata_dispatcher.dart: SONG CREATE 성공 응답의 다른 ID를 기존 AccountStore.applyCanonicalSongReceipt에 전달한다. 트랜잭션이 실제 반영됐을 때만 승인 개수를 올린다. 이후 claim은 기존 hold/alias 순서 검사를 그대로 거친다.
- account_store.dart: 완료된 GATE 이후의 실제 호출 조건에 맞게 주석만 갱신. DB/보존 알고리즘 변경 없음.
- canonical_song_store_test.dart: 송신 경로에서 alias/원본 응답·개인 편집 보존, 보류 PATCH 불전송, 무관한 TAG 계속 전송, 반복 pass 중복 방지, 잘못된 status/envelope/MANUAL 및 같은 ID, 전송 중 소유권 상실 회귀를 추가했다.
- 현재 모델 코드 검토: 원본의 서버 값 덮어쓰기 금지와 개인 편집 보존을 실제 diff/mapper와 대조했다. decoder 및 mapper 내부 이중 검증을 유지하며 201·같은 ID를 자동 매핑하지 않는다. 401/403 조기 중단·계정 requireActive·DB 오류 rollback/전파를 변경하지 않는다. 불완전한 개인 편집 병합/hold 해제/목록 송신을 완료로 확대하지 않는다.
- 선택 이유: 동기화·계정 DB 경계라 높은 추론을 요구하는 범위. 현재 모델이 직접 수행했으며 모델/추론 자동 변경 및 실제 Standard tier는 확인하지 못해 적용했다고 주장하지 않는다. 새 세션 위임 없음.

## 실제 검증

작업 디렉터리 apps/mobile:

```text
flutter test --no-pub test/canonical_song_store_test.dart test/metadata_dispatcher_test.dart test/mutation_retry_test.dart test/sync_controller_test.dart --reporter expanded
flutter analyze --no-pub
```

- 최종 테스트 **115 통과**, 종료 0. 분석 **No issues found**, 종료 0. SQLite fixture의 다중 DB debug 경고는 있었으나 실패는 없다. 기존 rollback/파일 보존/높은 revision/지연 ACK 및 인증 후속 차단 회귀를 유지했다.
- 최초 연결 110 통과 후 경계 사례 5개를 추가해 재검증했다. 테스트 삭제·약화 없음.
- dart format은 파일 정리 후 telemetry 경로 접근 거부가 발생해 정상 권한으로 완료했다. 환경 문제이며 제품 수정 실패로 세지 않는다.
- 상세 로그: .local/workflow/p10-04b-connect-tests.log, p10-04b-connect-analyze.log. 핵심 결과는 이 문서에 보존한다.
- 현재 폰 설치 APK는 2e6bd88이다. 새 CONNECT 실기를 실행했다고 기록하지 않는다. 변경은 송신/SQLite 경계이며 이번 범위는 자동 통합 회귀로 검증했다. 별도 P10-03b 비어 있지 않은 큐 실기 준비 상태는 유지한다.

## 커밋/CI와 다음

이 문서를 포함하는 CONNECT 커밋은 Git history로 식별한다. 현재 로컬 검증·코드 검토 통과, 커밋/push/정확 SHA CI 확인 전이다. CI 완료 근거는 후속 기록으로 추가한다. 전체 P10-04 완료가 아니며 개인 편집 선택/안전한 hold 해제 등 후속 계약은 남아 있다. 사용자 확인 대기 0건. 다음은 CI 진행 중에도 공유 파일이 겹치지 않는 P10-05의 서버 변경 조회 구현을 실제 코드/원본과 대조해 수행한다.

후속 실제 결과: ab5dd8173c29456c9eab28d27b1bd93418cdc854 커밋/push. Development workflow run36667867244의 Check source provenance and failure handling 실패. 로컬 Python19 재현에서 기존 운영 테스트가 active 작업을 fixture에서 삭제해 coverage 참조 무결성을 깨는 ValueError 확인. 제품 테스트 실패가 아니다. 실제 inventory 검증을 유지하고 준비 상태는 격리 fixture로 검증하도록 수정, 선행 export.integrated 누락 시 차단 검사도 추가했다. Python19 재실행 통과. 테스트/CI 삭제·약화 없음. 보정 후 정확 SHA CI를 다시 확인한다. P10-05는 ‘초기 스냅샷’이며 증분 변경 조회(P10-06)와 구분한다.
