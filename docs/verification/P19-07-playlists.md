# P19-07 외부 탐색 문맥 유지

- P19-09까지 원수 승인, 요청·관측 gpt-6.1-sol/medium. 기준 b0c80eb4037cae6303d4b74753c2a559799339b2, 원수 begin 측정 확인.
- 원본 계획서 v1.0 문단887~889 직접 대조: 검색·차트·KY→TJ 이동 중 대상 목록 유지, 취소 시 추가 없음, TJ 선택 뒤 처음 선택한 목록으로 복귀. R007/R081·V34/V38, 기존 C02 금영 자동 매핑 금지 유지.
- 기존 SearchIntent/KaraokeSelection, KaraokeSearchScreen/PopularChartScreen을 재사용한다. 플레이리스트 상세에서 검색·차트 진입, 동일 intent의 명시적 TJ 선택만 반환, 원래 상세 스택 유지. KY 제목은 TJ 검색 입력으로만 이동하며 번호 변환·금영 후보 저장 없음.
- 저장 경계에서도 목적·목록 UUID·복귀 경로를 대조한다. 최신 로컬 부모로 새 요청을 준비하고 기존 미확정 변경 중 새 요청을 막는다. 이미 저장한 양수 base_revision 재작성 없음. 기존 계정 lease/인증 검사를 사용하며 계정 변경은 실패로 처리한다.
- 영향2개 PASS: 차트 KY→TJ 실제 선택·취소/원래 경로 복귀, 실제 SQLite의 외부 문맥 거절·선택한 목록에 정확한 토큰 요청·ACK·재열기. 기존 공급자 선택·목록 저장 회귀는 전체 검사에서 확인한다.
- 화면 변경으로 설치본 확인 필요. 연결·잠금 상태를 실제 확인하고 AI가 탐색/취소/저장/재시작 검사한다. 전체 로컬 검사·현재 모델 검토·실기·최종 SHA 필수 CI는 완료 후 기록한다.

## 실제 검증·현재 모델 검토
- Flutter 전체975개 PASS(로그2분31초), 최종 analyze 0문제, 검증 APK 빌드 PASS(40.22초), diff --check PASS. 첫 분석의 import 순서5건만 정리 후 재분석 통과. 기능 변경/검사 약화 없음. 전체 검사 로그와 최종 결과는 Git 제외 .local/workflow/p19-07에 보존한다.
- 현재 모델 gpt-6.1-sol/medium이 원본 설계서 문단162와 계획887~889, 최종 diff·검사 결과를 별도 대조했다. 동일 intent만 반환, 다른 목록 목적지 거절, 사용자 TJ 재선택, 원래 route/IndexedStack 보존, 계정 lease 및 pending 부모 변경 차단, 원 토큰 보존 확인. 별도 AI/Reviewer 호출 없음.
- SM_A546S 기존 데이터 보존 install -r 성공. 원래 빈 목록→인기 차트→금영01234→TJ에서 찾기(제목 미리 입력/TJ00555)→뒤로 두 번 시 빈 목록 그대로. 같은 경로에서 명시적 TJ 곡 선택 후 원래 목록으로 복귀·미등록TJ후보 한 행 추가. force-stop/재시작 후 동일 후보 한 행 유지. 증거 cancel-preserved/selected-tj/selected-tj-sheet/saved/restarted-ready.xml. 합성 응답·별도 계정의 실제 DB 검사이며 운영 외부 API 검사로 확대하지 않는다.
- 사용자 직접 할 일0건. 최종 SHA의 영향 Flutter CI 대기 후 P19-08.
