# P10-06m — 초기 사본의 곡·태그·녹음 업무 데이터 반영

2026-10-01. P10-06 변경 수신과 P10-05 초기 사본의 후속 연결. 원본 plan p00590~592 및 기존 P10-06g/i/l 검증 근거를 따른다. 초기 사본의 업무 사본 미반영 상태에서 변경 목록이 비어 있으면 과거 metadata_copies가 남는 경로를 보완한다.

## 변경 및 현재 모델 검토

- ChangeFeedStore가 증분 페이지 트랜잭션 안에서 영구 삭제 표식 뒤 초기 SONG/TAG/RECORDING을 투영한다. 빈 페이지와 이전 앱에서 이미 커서가 진행된 경우도 포함한다.
- 원본은 보존하고 곡·태그의 업무 필드만 명시적으로 선택한다. 녹음은 기존 동일 token의 파일 명세/태그 묶음 투영을 재사용한다. 소유자·ID·도메인 값·중복 UUID를 검사한다.
- 더 높은 기존 revision/영구 삭제 표식은 되돌리지 않는다. 기존 미전송 입력·mapping hold·변경 큐가 있으면 local_payload를 보존한다. 큐 원문·wire·시도 이력·원본 사본·녹음 파일을 지우거나 수정하지 않는다.
- 초기 적용과 증분·커서가 같은 트랜잭션이다. 중간 실패/계정 변경은 전체 롤백한다. 읽기는100행씩 하며 불필요한 같은 revision 재쓰기를 생략한다. 앱 업그레이드에 대한 적용 마커가 없으므로 현재는 페이지마다 초기 대상 행을 대조한다. 대규모 계정 성능은 향후 실제 데이터 규모 검증 대상이며 미측정 시간을 기록하지 않는다.
- 원본의 다른 관계/클라우드 자산 적용은 별도 후속 범위다. 전체 P10-06 완료 아님. USER-025(c7df3fd) 실기를 이 변경으로 확대하지 않는다.

## 실제 검증

- `flutter test --no-pub test/change_feed_store_test.dart test/change_feed_receiver_test.dart test/snapshot_download_store_test.dart test/resync_integration_test.dart`: **48 PASS**.
- 현재 모델 검토에서 업그레이드 후 진행된 커서를 발견해 최초 커서 조건을 제거한 뒤 store/resync 관련 **23 PASS** 재검증.
- `flutter test --no-pub test/change_feed_store_test.dart --plain-name 'upgrade projects baseline'`: 추가 회귀 **1 PASS**.
- 변경7 Dart 파일 정적 분석 및 추가 테스트 분석 **No issues found**.
- 빈 페이지의 최신 초기 값 반영·미전송 입력 유지·반복 적용 불변·기존 더 높은 revision·tombstone 유지·보관 태그·후반 잘못된 태그에서 앞선 곡 반영까지 롤백을 확인했다. 기존 녹음 관계·파일·재동기화 전체 순서 검증도 유지했다.
- 통합 테스트는 모든 비사본/비커서 테이블 동일을 유지하고, 갱신 대상 metadata_copies는 서버 revision/payload/갱신시각만 제외한 각 열의 원값과 행 개수까지 대조한다. 이 서버 사본 갱신은 새 요구 동작이며 로컬 입력 보존 검사를 줄인 것이 아니다.
- 공유 snapshot-wire.json은 숫자 해시의 golden 자료이므로 변경하지 않았다. 실제 업무 필드를 가진 테스트 자료를 별도 helper에서 만들고 올바른 manifest hash를 계산하여 기존 무결성 검사를 통과시킨다.
- 테스트 보완 이력: 기대값 텍스트 치환이 다른 롤백 검사에 퍼진 오류를 발견해 해당 변경만 원복하고 대상 테스트 하나로 한정했다. 추가 테스트의 타 계정 자료는 DB CHECK에서 먼저 거절되어, 정상 계정의 잘못된 태그 이름으로 롤백 경로를 검증했다. DB 제약/검사를 약화하지 않았다. 제품 문제 3회 실패로 오인하지 않는다.

로그: .local/workflow/p10-06m-test.log, p10-06m-final.log, p10-06m-upgrade.log. 현재 모델 직접 구현 및 별도 코드 검토 단계이며 모델 변경/독립 검수라고 주장하지 않는다. 대상 SHA는 Git 이력, 정확 SHA 필수 CI는 후속 통합 기록에서 확인한다.
