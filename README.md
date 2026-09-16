# Song_Record
노래방 노래 검색, 녹음, 노래의 다양한 정보 기록 관리 앱

## 기준 파일

| 자료 | 파일명 | 버전 | SHA-256 | 구현할 때의 역할 |
|---|---|---|---|---|
| 설계서 | `노래기록앱_구현설계서_v1.11.docx` | v1.11 | `957786385b081e52cdca2f83250b712701bcb63a73df63df47c1983a5916fe36` | 기능·데이터·API·삭제·동기화·보관 정책 |
| HTML | `b-playlist-ui-v1.11.html` | v1.11 | `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555` | 화면 배치·버튼·화면 이동·상호작용 참고 |
| UI_REFERENCE | `UI_REFERENCE.md` | HTML v1.11 대응 | `b62babdba6a124277e57e57b56a605325cd961e4040c73cca8a9c03a96a53d17` | 공통 UI 구성과 조작 규칙 |
| 색상 JSON | `ui_reference_palette.json` | 스키마 v1·HTML v1.11 대응 | `88ad5972f79424629b87698760ca98894c4f65fc23d9448bcec1effc4d12d83b` | 색상·글자 크기·간격·컴포넌트 치수 |
| 코드 구현 참고 사항 | `코드 구현 참고 사항.txt` | 버전 표기 없음 | `9f6a8df4f0908e61ca8a3612b83f4f26610ccdb0cec5165a541a73cb72bf10bd` | 자료별 적용 범위와 구현 기준 |

## 대응 관계 확인

- 설계서와 HTML의 기준 버전은 모두 `v1.11`이다.
- `UI_REFERENCE`는 `b-playlist-ui-v1.11.html`을 기준으로 작성됐다.
- 색상 JSON의 `source.sha256`은 HTML의 실제 SHA-256과 일치한다.
- HTML 기준 SHA-256: `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555`
- 따라서 설계서 v1.11과 HTML·UI 규칙·팔레트의 대응 관계를 확인할 수 있다.

## 현재 구현 기준과 변경 계약

- [요구사항 목록](docs/requirements.md) · [진행 기록](docs/progress.md)
- [D01: A안 구현 기술 결정](docs/decisions/D01-implementation-stack.md) · [버전 기준·고정 대상](docs/contracts/toolchain-versions.md)
- [D02: 공통 정렬](docs/decisions/D02-sort-order.md) · [D03: 날짜·동률](docs/decisions/D03-date-boundaries.md) · [D04: 기기 파일 필터](docs/decisions/D04-device-file-filter.md)
- [P00-05 공통 입력·기대 결과·페이징 사례](docs/contracts/P00-05-examples.md)
- [D12: 일간·주간·월간 인기곡 채택](docs/decisions/D12-popular-periods.md)
- [P00-03 외부 데이터 조사 및 실제 호출 결과](docs/research/external-data.md)

2026-09-16 사용자 승인: 차트는 과거 연월 선택 대신 Manana의 TJ/KY 일간·주간·월간 인기곡으로 구현한다. 원본 설계서·구현계획서·HTML·UI_REFERENCE의 차트 관련 내용과 충돌하면 D12를 우선 적용한다. 원본 파일과 해시는 보존한다. API 호출 성공과 이용 허용·집계 정확성·앱 통합 검증은 구분한다.

P00-05 완료: 추천 조합을 D02~D04로 확정했다. 정렬·날짜·기기 파일 필터의 세부 구현 계약은 해당 결정서를 따른다. 원본 자료는 보존하며 실제 앱·서버 검증 결과는 후속 구현 단계에서 기록한다.
