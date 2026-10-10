# P16-05 — 인기곡 게시본 조회 API (D12, 원수)

- R087/R088/R090·D12: GET /v1/charts/popular?brand=TJ|KY&period=DAILY|WEEKLY|MONTHLY 구현. 이전 연월 API는 생성하지 않는다. 현재 계정·기기를 인증하고 반환 전에 같은 세션을 재검증한다. 정상/업무 오류 no-store. 다른 HTTP 메서드 차단.
- ChartQuery는 읽기 전용 REPEATABLE_READ 트랜잭션에서 같은 scope의 PUBLISHED 포인터·항목만 읽는다. immutable snapshot ID로 원본 순서/번호 선행0 유지, 완전성·scope 검사. 개인 곡/녹음/change_log/외부 제공자에 접근하지 않는다. 최초 미게시/빈·손상 게시본은 503 CHART_SOURCE_UNAVAILABLE, retryable=true. 다른 scope fallback 없음.
- 최신 수집 attempt와 게시 attempt가 다르면 이전 동일 scope의 자료·수집 시각·revision 그대로 stale=true. 동일하면 false이며 제공자 집계일/갱신 주기/최신성을 추정하지 않는다. 운영 실데이터 수집·저장은 이용 조건 확인 전 기존 차단 유지.
- TJ 항목은 기존 SourceTokens를 재사용해 원본 번호/제목/가수/manana:tj 출처와24시간 만료 증명을 반환. KY source_token=null, 자동 TJ 번호변환/계정별 matched_song_id 공용 캐시 없음. 기존 P15 등록·재검증 정책 유지.
- 로컬 일괄 services/api/gradlew.bat -p services/api test bootJar --console plain: 전체673 중592 성공/1 실패/80 MySQL 로컬 제외. 실패는 API 목록 검사에 신규 컨트롤러 미등록; 구현 동작 테스트5개 통과. 목록 추가 후 동일 검사 --tests com.ksh321.songrecord.api.auth.ApiContractTests 및 bootJar PASS. 전체를 무조건 재실행하지 않고 변경 영향만 재확인했다. 초기 테스트 import 누락은 별도 컴파일 오류1회 수정, 동일 근본 원인 실패로 합산하지 않는다.
- 계약 .local/workflow/contract-venv-modern/Scripts/python.exe infra/scripts/verify_api_contract.py: OpenAPI·local refs·security·7wire·141boundary PASS.
- 현재 사용자 지정/실제 관측 gpt-6.1-sol/medium 직접 별도 코드 검토: D12·실제 diff·검사 결과, 같은 generation 읽기·stale 의미·재인증·TJ/KY 토큰·기존 개인 동기화 미변경 대조 PASS. 제공자 호출 연결 없음, DB writes 없음. 필수 폰 실기 없음(API 작업); 다음 화면 구현부터 설치본 실기 필요.
- 변경: ChartQuery/ChartResults/ChartController/ChartQueryConfiguration.java; GlobalExceptionHandler.java; ChartQueryTests/ChartHttpTests/ApiContractTests.java; docs/contracts/openapi.yaml. 최종 정확 SHA 필수 CI 전 미완료.
- 학습: 같은 스냅샷을 읽는 트랜잭션과 게시 시도를 분리하면 수집 중에도 완전한 이전 자료를 보여주고 실패를 최신 자료로 오인하지 않는다.
