# P00-03 외부 데이터 조사

조사일: 2026-09-16. 결정: [D12](../decisions/D12-popular-periods.md).

## 인기곡 실제 호출

GET https://api.manana.kr/karaoke/popular/{brand}/{period}.json

| 브랜드 | 기간 | HTTP | 곡 수 | 고유 번호 수 | 소요 초 |
|---|---|---:|---:|---:|---:|
| tj | daily | 200 | 100 | 100 | 16.55 |
| tj | weekly | 200 | 100 | 100 | 16.39 |
| tj | monthly | 200 | 100 | 100 | 16.81 |
| kumyoung | daily | 200 | 100 | 100 | 14.63 |
| kumyoung | weekly | 200 | 100 | 100 | 14.86 |
| kumyoung | monthly | 200 | 100 | 100 | 14.41 |

6개 모두 첫 요청에서 비어 있지 않은 JSON 배열, 올바른 brand, no/title/singer 필드, 중복 없는 번호를 확인했다. 측정은 이 실행 환경의 단일 표본으로 SLA나 제공자 고유 지연을 보장하지 않는다.

- 반환 필드: brand, no, title, singer, composer, lyricist, release.
- rank, 집계 시작/종료, 원본 갱신 시각은 이번 응답에 없었다. release는 곡 수록 정보이며 차트 집계 월이 아니다.
- 금영 daily/weekly는 응답 바이트 SHA-256이 같았다. 각 경로 응답 성공은 확인했지만 실제 기간별 집계 차이와 최신성은 확인되지 않았다. 서로 다른 결과를 임의 생성하지 않는다.
- TJ 3개 기간은 서로 다른 응답 해시였다. 이것만으로 기간 경계/최신성을 입증하지 않는다.
- 원문 곡 목록은 저장하지 않고 검증 수치·응답 해시만 [probe JSON](manana-popular-probe.json)에 기록했다.

## 검색 후보

Manana 문서에 song/{title}/{brand}.json, singer/{singer}/{brand}.json, no/{no}/{brand}.json 경로가 있다. TJ=tj, KY=kumyoung이다. 앞선 조사에서 TJ 번호 및 금영 가수 검색의 응답을 확인했으나 일부 검색은 시간 초과였다. 이번 호출 검증은 인기곡 6개에 한정한다. 검색 전체 회귀·3초 제한 내 사용성은 P15에서 검증한다.

## 판정 및 남은 확인

- 인기곡 기술 채택: 6개 경로 호출 성공, 사용자 요청에 따라 D12로 확정.
- 과거 연월 차트 및 브랜드별 완료 월 2개 요구: D12로 대체. 해당 기능 구현하지 않음.
- 조회 지연: 약 14~17초였으므로 사용자 화면에서 원본 API를 매번 직접 기다리지 않는다. 서버 게시본/백그라운드 갱신을 사용하고 캐시 보관 허용 조건은 출시 전 확인한다.
- 제공자 홈페이지 FAQ는 무료/호출 제한 없음으로 안내하나 상업적 앱 표시·개별 곡 저장·차트 보관/캐시 범위는 별도 확인 필요. 이번에 제공자에게 메시지를 보내거나 허락을 받지 않았다.
- P00-03 상태: 기술 조사·채택 완료, 이용 조건 확인 대기. P16 앱 통합 테스트와 V41 통과를 의미하지 않음.

## 출처

- [Manana 인기곡 문서](https://api.manana.kr/karaoke/popular/joysound/daily)
- [Manana FAQ](https://api.manana.kr/)
- [곡명 검색](https://api.manana.kr/karaoke/song/missing)
- [가수 검색](https://api.manana.kr/karaoke/singer/nao)
- [번호 검색](https://api.manana.kr/karaoke/no/26471)
