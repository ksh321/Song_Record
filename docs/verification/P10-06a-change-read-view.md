# P10-06a — 증분 변경 수신: 서버 변경 페이지 검증·일관 조회

2026-10-01. 원본 계획 p00590~592, 설계 p00311~312 및 R040의 후속 서버 기반이다. 원본 단계 선행 p00189~191과 기존 P07-05 커밋 순서/90일 로그를 대조했다. P10-05n 폰 실기를 이 범위의 선행으로 추가할 근거가 없어 독립 작업으로 선정했다. 전체 P10-06 완료나 앱 증분 수신 완료는 아니다.

## 구현

- ChangeWindow: after/head/retained_from_seq 경계, 최대100+lookahead1, 연속 순번, 누락·중복·잘못된 정렬, 실제 만료를 검사한다. 반환한 마지막 항목까지만 nextSequence로 삼는다. 삭제 표식/개별 revision/payload는 재해석하지 않는다. Long.MAX_VALUE 계산도 넘치지 않는다.
- ChangeReadView: 동일 계정의 head·보관 경계·만료 행·페이지를 짧은 read-only REPEATABLE READ에서 읽는다. 아직 청소하지 않은 만료 로그도 CURSOR_EXPIRED다. 다른 계정의 만료 로그는 영향을 주지 않는다. 조회 후 읽기 트랜잭션을 닫고 세션을 새로 확인해 폐기된 세션으로 자료를 반환하지 않는다. 15초 결과 기한을 확인한다.
- MySqlChangeReadViewTests: 테스트마다 p10_change_test_<무작위> DB만 만들고 그 DB만 정리한다. 실제 InnoDB에서 head 조회 후 다른 연결이 새 변경을 커밋해도 기존 페이지에 시점이 섞이지 않고 다음 조회로 받는지 검증한다. 기존 필수 Idempotency MySQL workflow에 추가했다. 기존 검증/보호/예산을 약화하지 않는다.

## 실제 검증·현재 검토

```text
gradlew.bat test --tests '*ChangeWindowTests' --tests '*ChangeReadViewTests' --no-daemon
```
로컬 **14 PASS, MySQL7 skip**, 종료0. Windows Docker가 USER-023으로 차단돼 실제 MySQL 성공으로 기록하지 않는다. 기존 JAVA_TOOL_OPTIONS의 실행별 socket 경로 보완만 적용하고 finally 복원했다. 상세 .local/workflow/p10-06a-read-view-test.log.

현재 모델이 원본 요구사항·실제 diff·결과를 별도 대조했다. 계정 필터를 모든 쿼리에 바인딩하며, 마지막 세션 확인을 오래된 RR 시점 안에서 하지 않는 점을 확인했다. 누락 행은 cursor 점프나 정상 빈 페이지로 취급하지 않는다. 새 작업자 위임 없음. 인증/동기화 위험도에 높은 추론이 적합하나 실행 모델/속도 변경을 관측했다고 주장하지 않는다.

실제 MySQL7 및 exact SHA 필수 CI는 push 후 확인한다. HTTP 경로/응답 계약 및 앱의 원자 반영은 아직 연결하지 않았다. 이 기반만으로 p10.receiver나 전체 P10-06 완료를 만들지 않는다. 사용자 폰 조작은 이 서버 기반의 완료 조건이 아니다.
