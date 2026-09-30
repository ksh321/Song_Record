# P10-04b-EXPORT — 복구 내보내기 보존

요구: canonical alias/편집/보류/대체 관계와 원본 큐 논리 순서를 복구 자료에 보존한다. AccountStore.recoveryData에 schema_version 및 원본 queue rowid 기반 local_order를 포함하고 테이블별 결정적 순서로 출력한다. 데이터 쓰기나 importer 구현은 포함하지 않는다.

변경: account_store.dart, account_store_test.dart, canonical_schema_test.dart, canonical_song_store_test.dart.
검증: 기존 final-test 로그 69 통과/Windows symlink 1 skip, flutter analyze --no-pub 문제 없음. 이번 검수 동안 제품 변경 없어서 같은 전체 테스트를 반복하지 않음.
별도 검수: USER-019 한정 승인 후 Reviewer-20260930-114320-226, Astra/high(계정 DB/보존 계약 위험). P1/P2 없음 PASS. CLI 모델/추론 확인; Standard/default·Fast 끔 요청, 실제 tier 미확인. 원본 자료·실제 전체 파일·diff·정제된 테스트 결과를 제공했다. 원본 기기 로그/개인 데이터/키/로그인 설정 제외.

대상: HEAD 5fd3e126c71dcedfd9598d9defbe0a98e772b614 위 분리 변경. 이 문서를 포함한 커밋 SHA는 Git history로 확인. commit/push/CI는 실행 후 progress에 별도 기록. 원자 매핑 dispatcher 연결과 개인 편집 보존 후속은 아직 남았다. 기존 폰 실기 및 사용자 승인 범위를 확대하지 않는다.


최종 커밋 **bf2ce110c9ae13bf6fd19bbb329319c2c102998e**, 일반 push 완료. 필수 CI 4개/필수 job 모두 success: CI36661425538, API36661425541, MySQL36661425501, Development workflow36661425550. 전체 P10-04 완료로 확대하지 않는다.
