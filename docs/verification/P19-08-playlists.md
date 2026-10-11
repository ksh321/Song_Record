# P19-08 — 순서 변경과 충돌

## 요구사항과 변경
- 원본 계획서 v1.0 문단 890~892: 전체 활성 PlaylistItem ID와 Playlist revision을 받아 한 트랜잭션으로 순서를 저장한다. 중복·누락·다른 목록 ID를 거절하고 동시 편집은 409로 처리한다.
- 목록 상세에 순서 편집을 연결했다. 취소는 저장하지 않고 확정한 전체 ID 순서만 불변 요청으로 큐에 넣는다. 편집 중 계정·대상 목록 변경 및 선행 미동기화 작업은 거절한다.
- PUT /v1/playlists/{id}/order는 같은 계정의 현재 활성 항목 전체와 대조한다. 부모 revision 잠금·한 번의 증가·position 재부여·변경 피드·멱등 응답을 같은 트랜잭션에서 처리한다. 숨긴 항목·Song·Recording 내용은 변경하지 않는다.
- 모바일 수신은 응답의 전체 ID·위치·부모 revision·항목 정체성과 계정을 검증한 뒤 하나의 DB 트랜잭션으로 반영한다. 잘못된 응답은 순서를 그대로 두고 동일 요청으로 재시도한다.
- 재시도 검사에서 PUT/order의 고정 요청 복원 경로 누락을 발견해 retry_controls에서 동일 경로·본문·hash 검증을 재사용하도록 수정했다.

## 검증과 별도 코드 검토
- 영향 검사 playlist_order_test.dart: 2개 PASS. 취소/확정, 중복·누락 거절, 손상 응답 롤백, 같은 hash 재전송, 재시작 보존.
- 서버 PlaylistTests 영향 검사 PASS. 중복·누락·다른 목록, 역순 위치, 멱등 재전송, 오래된 revision, 빈 목록 검사.
- 현재 모델 gpt-6.1-sol/medium에서 구현 후 별도 검토: 원본 완료 조건·실제 diff·큐 불변성·응답 검증·계정 분리·삭제 후 늦은 ACK 방어·변경 피드 대조. 하위 에이전트 호출 없음.
- 전체 로컬 검사·설치본·최종 SHA 필수 CI는 진행 중이며 결과를 확인한 뒤 아래에 기록한다. MySQL 동시 편집 실제 검사는 CI에서 확인한다.
- 사용자 USER-087 잠금 해제 회신 ㄱ 후 런처 전경 확인. 폰 알림 서버 접수이며 수신 확인으로 간주하지 않는다.

## 변경 파일
- API PlaylistService/Controller/Configuration, PlaylistTests/MySqlIdempotencyTests, OpenAPI.
- 모바일 playlist_library/detail/order_picker, mutation_request/dependency_planner/playlist_addition_receipt/account_store/retry_controls.
- playlist_order_test, 검증 전용 playlist_addition_fixture/playlist_order_verification.

## 학습 개념
- 전체 순서 저장과 revision 비교는 여러 항목의 부분 저장과 오래된 편집의 덮어쓰기를 막는다. 멱등 재전송은 최초 요청의 식별자와 본문을 그대로 사용한다.

## 최종 로컬·설치본 결과
- Flutter 전체 977개 PASS(168.07초), API build --offline PASS(69.86초), 최종 analyze 0문제(9.01초), API 계약 PASS(3.43초), APK PASS(42.23초), diff --check PASS. 최초 중괄호 형식 1건과 EOF 공백만 정리했으며 테스트 약화 없음.
- SM_A546S install -r 성공, 합성 응답·별도 계정·실제 SQLite 검사. 최초 TJ 검사 곡→직접 등록 곡, 위로 이동→취소 후 그대로, 다시 위로 이동→순서 저장 후 직접 등록 곡→TJ 검사 곡. 재시작 후 동일 순서 보존. 취소/저장 bounds 하단 2149/2160으로 시스템 내비게이션 시작2205보다 위다. XML 증거 edit-ready/cancel-preserved/saved/restart-ready 보존.
- 원본·최종 변경·실제 결과 별도 검토 완료. MySQL 실제 동시 편집과 최종 SHA 필수 원격 3종 CI는 푸시 후 대조한다.
