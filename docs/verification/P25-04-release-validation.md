# P25-04 UI와 변경점 검수

원본 계획 p01080–p01081·R128/X01–X12. USER-104가 추가 실기를 출시 전 미완료로 보존하고 후속 검수·준비를 이어가는 순서 예외를 승인했다. P25-03 전체 완료 사실은 만들지 않았다. 원수 P25-03 현재 범위 finish→P25-04 begin, 요청/관측 6.1 Sol/medium.

## 현재 소스 검수

- 원본 HTML 최종 CSS·UI_REFERENCE v1.11 보완 규칙·팔레트의 색상/글꼴/치수와 현재 AppTokens/AppTheme·공통 선택/키/탐색 시트·곡/녹음/목록 화면을 대조했다. 원본6개 수정 없음.
- 강조색8개/초기 블루, 독립 녹음 빨강·원64/네모32/링82, 키 배지 의미/문구, 시트 반투명48%·180ms·모션 감소·SafeArea/스크롤, 내비76과5개 탭, 정렬/버전/상태 표시를 확인. HTML의 고정 프레임을 앱 크기로 사용하지 않는다. Material 내비의 세부 장식 치수를 HTML의 모든 CSS px와 동일한 픽셀 이미지로 인증한 결과는 아니다.
- 등록/편집/삭제/필터/곡 선택의 확정과 취소, 원래 목록 스크롤·탭 문맥 복귀, 미정과 취소 구분, 불러오기/오류를 빈 결과로 위장하지 않는 동작을 실제 기존 검사와 코드로 대조했다. 새 제품 결함/소스 수정 없음.

## X 검수의 근거와 범위

| ID | 현재 검사·검토 근거 | 판정 범위 |
|---|---|---|
| X01 | song_edit_test, song_screen_acceptance_test, 입력 길이/Unicode 계약 | 언어 제거·2000자·저장/취소 회귀 PASS |
| X02 | my_songs_test, my_song_pages_test, p03_domain_rules_test |5정렬·NFC/동률ID·그룹·ACTIVE/SAVED/파일 무관·페이지 초기화 PASS |
| X03 | theme_contract_test, tab_navigation_test, song_screen_acceptance_test, 공통 시트/키 검사 |8강조색·작은 화면/큰 글꼴/키보드·취소/스크롤/탭·모션 감소의 프로그램 검사 PASS; 전체 기기 시각/접근성 인증 아님 |
| X04 | recording_filter_test·recording_catalog_test | AND/태그1·미정/미연결·기간 경계·초기화/취소/조건수/0건 PASS |
| X05 | classification_screen_test와 분류/저장/편집 검사 | 고정 컨디션·태그/archived 참조·취소/과거 이름 보존 PASS |
| X06 | recording_relink_test·import_data_timezone_test·시각/연결 검사 | 당시 정보/시간대·재연결/복원 관계 모델 PASS; 실제 서비스 복원은 미완료 |
| X07 | account_store_test·auth_session_test·파일/계정 검사, P25-02 실제 MySQL | 저장소/파일/토큰·로그아웃 격리 모델 PASS; 실제 소셜 재로그인/서비스 통합 실기 미확인 |
| X08 | offline_trash_test·trash_workflow_test·change_feed_store_test | 기기 시각만으로 삭제하지 않음·권위 있는 삭제 수신/보존 PASS |
| X09 | recording_catalog_test·recording_list_test·device_file_cleanup_test | 페이지 밖 로컬 일치/파일 변동/빈 결과 PASS |
| X10 | resync/snapshot/change_feed 관련 검사 | 만료·재시작·오프라인 초안/파일 보존 PASS; P25-02 lease/UTC MySQL 회귀도 PASS |
| X11 | recording_asset_projection_test·permanent_deletion_test, P25-02와 P24 백업/원장 근거 | 사본 정리/Recording 구분·generation 모델/복구 경계 대조; 운영 전체 연결/출시는 별도 게이트 |
| X12 | 예산/업로드/재시도·비노출 모델 검사, P25-02 및 P24 비용/운영 검사 | 예산 잠금 중 정보/기존 동작 보존·비밀 비노출 근거 대조; 실제 운영 잠금을 새로 강제로 적용하지 않음 |

검색 후보 개수는 실제 실행 실적이 아니다. 전체 앱 실행 목록은 보호된 `.local/workflow/p25-04/test-cases.json`과 JSON 원시 로그에 보존하며 표는 해당 기능 근거에 연결한다. requirements.md의 초기 ‘모두 미실행’ 문구는 최초 요구사항 분해 당시 기준으로 취급하고 현재 실행 상태와 혼동하지 않는다.

## 실행과 별도 검토

- 한 명령 `python .local/workflow/p25-04/run-ui-checks.py`로 flutter analyze --no-pub·flutter test --no-pub --reporter json 실행. 분석 지적0(명령74.98초), 전체1204 PASS/skip0/실패0(182.41초). 결과는 현재 c216aa95d220181a4235b73013352ae41d096cc9 제품 소스 기준.
- 현재 lib/test/API 변경0, 서버 책임 검증은 동일 소스의 P25-02 실제 MySQL91/서버774 및 정확 CI PASS를 재사용한다. 변경 없는 앱 빌드·서버 전체 CI를 반복하지 않는다.
- 현재 모델 별도 검토: 원본 기준·실제 소스/실행 결과·취소/미정·권한/데이터 보존·서버 권위/화면 샘플 구분 대조. 별도 모델/독립 에이전트 검수 아님.
- 추가 제조사·하한/최신 OS·새 물리 기기·실제 서비스 복원은 USER-104 승인에 따른 미완료 출시 조건. 공개 운영 배포/실제 베타 관찰/스토어 제출 완료로 확대하지 않는다. 다음 P25-05에서 V01–V48 실패/미실행·출시 게이트를 분리한다.

학습: 모델·위젯 회귀 통과와 실제 서비스/다른 기기의 검증은 서로 다른 근거다. 같은 결과를 반복 실행하는 대신 소스 지문·실행 범위·남은 조건을 함께 연결한다.
