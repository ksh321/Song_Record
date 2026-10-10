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
