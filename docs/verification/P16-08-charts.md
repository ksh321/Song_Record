# P16-08 — 양 브랜드·6개 기간 출처 검수

## 범위와 현재 판정
- 원수 요청/실제 관측: gpt-6.1-sol/medium. 최초 시작값 유지, 재개 실행 ID를 측정 원장에 연결했다.
- 선행 P16-07 최종 73b1ca1dfe0db271973488e493e3b18e79e17537 및 Flutter CI 38024695024 PASS. 이번 기준 SHA도 동일하다.
- D12·R090·V40/V41에 맞춘 기술 검수. 운영 실데이터 저장·캐시·재표시 허용 조건은 미확인이다. D12의 P16-08 이용 조건 확인 의무가 남으므로 전체 완료로 표시하지 않는다. 기존 P00-03-TERMS 출시 차단을 유지한다.

## 실제 제공자 연결 근거
2026-10-10 10:30:57 KST P16-01의 읽기 전용 실제 호출 결과를 재사용했다. 원본 곡 배열을 Git/검증 로그에 보관하지 않고 HTTP 상태·개수·필드·브랜드·해시·조회 시각만 기록했다. 매번 반복 호출하지 않는다.

| 브랜드 | 기간 | HTTP | 관측 곡수 | 관측 응답 시간 |
|---|---|---|---|---|
| TJ | DAILY | 200 | 100 | 0.19초 |
| TJ | WEEKLY | 200 | 100 | 0.20초 |
| TJ | MONTHLY | 200 | 100 | 0.06초 |
| KY | DAILY | 200 | 100 | 0.05초 |
| KY | WEEKLY | 200 | 100 | 0.05초 |
| KY | MONTHLY | 200 | 100 | 0.09초 |

- URL: https://api.manana.kr/karaoke/popular/{tj|kumyoung}/{daily|weekly|monthly}.json. 해당 브랜드만 반환, 정확 집계 시작/종료·제공자 갱신 시각 미제공. release는 집계 날짜로 해석하지 않는다. 100곡·응답 시간·최신성을 상시 보장하지 않는다.
- KY DAILY/WEEKLY 동일 SHA256 ad2c0e6b1917cdc1c28e384b2bd07a0bbfe38c358eb9c09aac86c45aa4850401. 같은 결과를 오류로 취급하거나 차이를 조작하지 않는다.
- 상세 근거: P16-01 검증 기록 및 Git 제외 .local/workflow/p16-01/live-probe.json.

## 연결 검증 추가
변경 파일: services/api/src/test/java/com/ksh321/songrecord/api/charts/ChartHttpTests.java.
- 신규 두 검사에서 실제 ChartCollection → Staging → 전체 유효성 검사 → 원자 Publication → Query → 인증 HTTP 경로를 연결했다. H2 개발 fixture만 저장하며 실데이터·사용자 DB에 쓰지 않는다.
- TJ/KY×3기간 모두 정상 전체 배열·순서·문자열 번호/앞자리0·브랜드/기간/출처/수집시각·no-store·TJ 원본 토큰 검증·KY 토큰 없음 확인.
- 각 조합의 빈 배열·필드 누락·다른 브랜드·중복 번호·잘린 JSON은 게시 실패 후 같은 조건의 원래 항목/게시 revision/수집시각 보존, stale HTTP 반환 확인.
- 각 조합의 NETWORK/TIMEOUT은 원인 분류와 최대2회 호출, 기존 정상 자료 보존 확인. 실제 멈춘 어댑터의 제한 시간·취소·뒤늦은 저장 금지는 기존 hungSourceTimesOutAndCannotStageLater에서 별도 검증한다.
- 같은 내용 재수집/기간별 동일 결과 정상 허용, revision 증가·stale 해제 확인. 최초 실패 시 다른 기간 게시본을 대신 반환하지 않고 CHART_SOURCE_UNAVAILABLE 확인.
- 운영 차단은 기존 liveCollectionIsBlockedBeforeFetchingAndOversizeNeverStages 및 fixtureCollectionRequiresExplicitDevelopmentOnlySwitch로 확인. 운영/default/bootstrap의 fixture 수집 비활성 유지.

## 일괄 로컬 검사 및 별도 코드 검토
- Java21 환경에서 services/api/gradlew.bat test bootJar 실행: 종료0, BUILD SUCCESSFUL(1분4초).
- 실제 JUnit XML 총675: 실행595 PASS, 실패0/오류0, MySQL 환경 조건 제외80. 제외80을 통과로 기재하지 않으며 필요한 원격 서버/DB CI를 확인한다. bootJar PASS.
- 로그: Git 제외 .local/workflow/p16-08/server-tests.log. 테스트 이름 존재만으로 통과 판단하지 않고 XML/실행 종료 결과 대조.
- 현재 모델 6.1 Sol/medium 별도 검토 PASS: D12/R090·원본 완료 조건·실제 diff·실행 결과 대조. fixture만 사용, 검사를 약화하지 않음, 인증/기존 개인 데이터/동기화/DB 스키마 변경 없음. source_token은 문자열만 비교하지 않고 기존 검증기로 원본 번호/브랜드/곡명을 확인. 다른 기간 대체 및 손상 배열 게시 금지 유지. 별도 모델/독립 에이전트 호출 없음.
- 앱 코드 변경 없음. P16-06 사용자6개 통과·P16-07 사용자 기능통과/하단해소 및 AI TJ/KY 취소 실기 근거 보존. 새 화면/조작이 없어 기존 실기를 다시 요청하지 않는다.
- 학습: 공급자 연결 성공, 앱 통합 동작, 이용 허가는 서로 다른 증거다. 데이터가 동일해도 유효할 수 있고 실패한 수집은 정상 게시본을 덮어쓰면 안 된다.

## 공급자 이용 조건 — 남은 완료 조건
- 공식 https://api.manana.kr/ FAQ는 Free/Not Limit만 표시한다. 서버 게시본 저장·캐시 기간·상업 앱 재표시·재배포 허용 범위는 명시 근거 미확인. 공개문서 재검색을 반복하거나 무료 문구를 포괄 허가로 해석하지 않는다.
- 공식 사이트 footer의 제공자 GitHub: https://github.com/yks118. 공개 프로필에서 사이트 https://manana.kr/ 및 @pure_ani 링크 확인. 아직 문의를 보내지 않았다. 현재 확인된 연락 경로와 실제 전송 화면은 승인 후 대조하며 지원하지 않는 GitHub 개인 메시지를 가정하지 않는다.
- 아래는 검토 가능한 문의안이다. 외부 전송은 사용자 명시 승인 후에만 수행한다. 답변/공개 허가 근거 확보 전 운영 수집을 켜지 않는다.

### 제공자 문의안
안녕하세요. Song_Record 노래 기록 앱에서 Manana의 TJ·금영 daily/weekly/monthly 인기곡 API 사용을 검토 중입니다. 다음 이용 범위를 허용하는지와 필요한 조건을 확인 부탁드립니다.
1. 반환된 번호·곡명·가수·배열 순서를 서버 공용 게시본으로 저장하고 앱 이용자에게 출처를 표시하여 보여 주는 것.
2. 정상 게시본과 장애 시 이전 게시본을 보관하고, 수집 시각 및 오래된 자료 표시와 함께 다시 제공하는 것. 허용 보관 기간·갱신 간격·호출 제한이 있다면 알려 주세요.
3. 무료 앱 및 향후 광고/유료 기능이 포함될 수 있는 앱에서 위 정보 표시가 가능한지.
4. 요구되는 출처 표기·라이선스·삭제 요청 처리와 API 자체 및 원 데이터 권리 범위에서 추가 확인할 사항.
현재 운영 수집과 실데이터 저장은 비활성화되어 있고 개발 합성 자료로 기능을 검증하고 있습니다. 적용 가능한 공개 이용조건 URL이나 허용 범위를 회신해 주시면 그 범위에 맞춰 구현하겠습니다.

## 다음
명시 범위 커밋·푸시 후 기준 SHA부터 필수 서버/DB CI 확인. 기술 검사 PASS와 이용 조건 대기를 분리하며 P16-08/P16 전체 완료 및 뒤 번호 착수를 하지 않는다.

## 최종 기술 검수 / 이용 조건 대기
- 커밋·푸시 SHA 37c1b2ba2410ce9bfdc811b18e96346d90ae21f9, push 범위 기준73b1ca1dfe0db271973488e493e3b18e79e17537.
- 필수 CI 38025890307: Scope/Spring Boot build and test/MySQL migrations and constraints 모두 success. Idempotency MySQL 38025890295 mysql success. 정확 SHA overall PASS. 앱 미변경으로 Flutter skipped는 정책상 제외이며 통과 실적으로 합산하지 않는다. API contract/Development workflow NOT_APPLICABLE도 통과 실적이 아니다.
- watcher 정상 PASS/오류0/종료, CI 알림 SERVER_ACCEPTED(폰 실제 수신 미확인). 제품 검사·빌드·CI 감시 진행0. 기존 Java daemon/ADB는 제품 검사가 진행 중이라는 근거가 아니다.
- 기술 검수는 완료했으나 D12의 이용 조건 확인 의무가 남아 P16-08/P16-PHASE 미완료. 운영 수집 비활성 유지, 뒤 번호 착수 안 함. USER-069 문의 진행 승인 필요: 승인 후 실제 연락 화면/전송 가능 여부를 확인하고 준비한 문의를 전달한다. 답변을 받아 저장/캐시/표시 범위를 대조한 뒤 재개한다.
- 제품 변경과 검증 문서는 위 SHA에 커밋되어 있다. CI 사후 결과·상태·직접 할 일 등 관리 기록은 로컬에 보존하며 기록만을 위해 새 제품 CI를 반복하지 않는다. 원수 finish는 전체 완료가 아니므로 실행하지 않고 최초 시작값 유지.

- 종료 대조: select_work.py --check-stop 종료0, WAIT/ready0/running0. USER-069 폰 알림 SERVER_ACCEPTED, 실제 수신 미확인. 문의 승인 질문을 현재 대화에 제시했다. 승인 없이 외부 전송하지 않는다.

## 2026-10-10 회신 반영 — 무료 범위 완료
- USER-069에 대한 사용자 회신은 문의 승인 대신 현재 무료 서비스에서 사용하고 유료 도입 때 이용조건을 검토하라는 결정이다. D12 후속 결정과 R090에 반영했다. 제공자 문의 미전송, 조건 미확인 사실 유지.
- 이에 따라 이전 절의 이용조건 대기/출시 차단/P16-08 미완료 표시는 현재 무료 서비스 범위에서 해제한다. 코드·검사·실기·SHA37c1b2ba2410ce9bfdc811b18e96346d90ae21f9의 CI38025890307/38025890295 PASS 근거는 그대로다. 검사 생략이나 실패를 무시한 완료가 아니다.
- 사용자 결정 반영은 문서/상태만 변경한다. 앱/서버 런타임 변경·실데이터 저장·운영 배포 없음. 현재 명시 개발 fixture 수집만 연결된 상태를 유지하며 실제 무료 운영 연결은 해당 배포 준비에서 구성·검증해야 한다.
- 별도 현재6.1 Sol/medium 검토: 결정·R090·검증 판정 일치, 제공자 허가로 과장하지 않음, 유료 전 확인 과제 보존. 문서 diff/비밀값 검사로 검증하며 동일 제품 CI를 다시 실행하지 않는다.

## 최종 완료 판정
- 무료 서비스 개발 범위 P16-08 및 P16-01~08 집계 완료. 제품 SHA37c1b2ba2410ce9bfdc811b18e96346d90ae21f9 필수 CI PASS, 후속 결정 문서 SHA0e76d24d81b211c9c55cdd2968f1045b22c7af42는 문서3개만 변경되어 원격 CI 불필요. 전체 이용허가 확보/운영 배포 완료가 아니다. USER-069 처리 완료, 직접 할 일0. 기존 최초 측정과 실행 ID 연결 유지.

- 종료: 선택기 --check-stop 종료0/ready0/running0. 완료 폰 알림 SERVER_ACCEPTED(실제 수신 미확인), 이후 원수 finish로 시간/구독 사용량 종료값 저장 및 로그 집계 감시 시작. 별도 AI 생성 없음. CI 사후/상태/완료 기록 미커밋 변경은 로컬 보존하며 불필요한 기록 커밋을 반복하지 않는다.

## 실제 배포 목표 및 목록 전환 정정
- 사용자 목표는 실제 서비스 배포다. 앞선 무료 개발 범위 완료는 기술 구현/합성 통합·기존 실기·CI에 한정하며 실제 운영 연결·배포 검증 완료가 아니다. 현재 코드의 live 수집 차단/fixture 전용 연결 상태는 그대로 미완료로 추적한다. 유료화 전 이용조건 확인 유예와 기술 연결 누락을 혼동하지 않는다.
- 사용자 요청으로 P16 상세 목록은 내가할일에서 제거하고 P17-01~08 원본 전체를 리스트업했다. 기존 통과 검사 반복 없음. 운영 연결·검증 남은 준비는 목록에 별도로 보존하고 P25-01/05/06 완료 판정 전에 대조한다. P17 실행 미승인·미착수.


## 2026-10-19 베타 인기 차트 운영 연결 누락 보완 — 진행 중

사용자는 노래방API미연결이 ‘인기 차트’라고확인했다. 실제AWS staging에서 chart_snapshot0/chart_item0/게시스코프0, CHART_SOURCE_UNAVAILABLE3회. 같은서버에서외부Manana 번호검색1개/월간차트100개 HTTP200·기본필드정상이라제공자장애와구분. 기존MananaChartSource/검증/원자게시/앱조회는있었지만 수집Bean은dev fixture만활성이고 live수집은항상차단돼있었다. 이전개발검증완료근거는보존하되실제베타수집운영연결완료로확대하지않는다.

보완은D12의2026-10-10무료서비스사용결정과기존검증계약에따른다. 기본live수집은비활성유지, staging/prod에서명시적live-enabled+storage-approved일때만실Source→staging→validation→publication이연결된다. fixture=false인일반호출은여전히거절한다. 별도scheduling-enabled까지켜진작업자에서만6개범위(TJ/KY×일간/주간/월간)를수집한다. API역할은세flag모두false. 초기5초/이후6시간은우리운영정책이며제공자갱신시각을추정하지않는다. 기존30초전체예산/동시2/재시도1/2MiB/전체검증/브랜드기간분리/원자게시/실패시이전게시본stale를유지한다.

변경파일: ChartCollection·MananaChartSource(주석), LiveChartCollectionConfiguration/Scheduling, LiveChartCollectionTests·실제MySQL chart검사, infra/experiment/runtime.py·test_experiment_runtime.py. 새schema/API경로/개인데이터삭제/업로드잠금변경없음. 정책파일은기존실험서버scope·enabled/storage_approved·300~86400초정수만허용하고기본6시간. 공개수집자료의보관정리는이번에추가하지않아기존게시본을임의삭제하지않는다.

영향검사 LiveChartCollectionTests/ChartCollectionTests PASS, runtime검사12 PASS. 전체도구315 PASS/0skip. 첫일괄MySQL검사는Docker엔진이없어DB생성전환경UNCONFIRMED, Docker공식CLI로기존엔진시작후동일소스지문을대조해315개는재실행하지않고실제MySQL전체/bootJar만이어간다. 개발/운영DB초기화·삭제없음. 최초gradlew호출경로오류는검사시작전환경오류로구분한다. 제품수정실패실적을만들지않음.

운영서버반영은아직미실행이며JAR/런타임정책준비·별도현재모델검토·정확범위배포허용뒤실제6범위수집/조회·폰차트표시를확인한다. 그전커밋/푸시/완료판정을하지않는다. 기존P16원수측정종료/완료이력은덮어쓰지않는베타후속보완이다.


### 실제 배포와 로컬 검사 결과 (2026-10-19)

전체 서버 834개 중 833 PASS·조건부 DeviceFlowHarness 1 SKIP, 실제 MySQL 92 PASS(전체의 부분집합), 도구315 PASS. 소스지문 전후 일치·bootJar PASS, 현재모델 별도 검토 지적0. JAR SHA256 `12f3c7a3b26a959260b4d6d6950e226f3af21dc39707d069e90b993c2e680557`. USER172 구체 반영안 ‘ㅇ’ 승인 후 적용했다.

최초 배포는 기존 백업/원장 실행 잠금에서 적용 전에 중단됐고 API/worker/DB·정책·차트0 보존을 확인했다. 재확인에서 BlockingIOError를 분류하고 기존과 같은 최대60초 직렬화로 잠금을 기다리도록 배포 절차를 보완했다. 잠금 제거/백업 중단/보호 우회는 하지 않았다. 환경 조정은 제품 코드 수정 실패와 구분한다.

실제 AWS API·worker 새JAR 반영·정상화, worker만 수집활성/API 비활성·6시간 주기 확인. TJ/KY 각각 DAILY/WEEKLY/MONTHLY 6개 스코프 게시/각100곡/revision1 확인. DB 컨테이너·계정2/녹음2·사용량253927/예약0/업로드잠금1·기존 자격/웹/작업자/관측정책·프록시 보존. 새키/스키마/네트워크 변경/개인삭제 없음. 폰표시는 아직 미확인(USER173), 실기 전 커밋/푸시 보류.


### P16-08 베타 후속 — 폰 표시 통과 및 커밋 준비 (2026-10-19)

USER173 질문의 TJ·금영 일간/주간/월간 6개 곡 목록·출처·수집시각에 사용자 ‘정상’ 회신을 받았다. 직접 행동0, 배포/로컬검사/현재모델 검토/실기 근거 일치. 이번 14개 파일만 비밀값 검사(기존12역할, 발견0)·선택 커밋·푸시 후 대상SHA 필수 서버/MySQL CI를 확인한다. 아직CI완료가아니다.
