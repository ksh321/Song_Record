# P16-01 — 인기곡 기간 계약 검증 (원수)

- 원본 P16-01 ID와 순서 유지. 확정 D12가 정확 연월·집계 시작/끝·완료 월 요구를 제공자 DAILY/WEEKLY/MONTHLY로 대체한다. R087~R090에 맞춰 적용한다.
- ChartScope: TJ→tj/KY→kumyoung, 3개 period의 공식 HTTPS source URI와 제공자 기준 기간 안내. 연월/최근30일/없는 브랜드를 기본값으로 치환하지 않고 400 VALIDATION_FAILED. Locale.ROOT로 터키어 환경에서도 DAILY URI를 보존한다. 정확 집계 날짜·업데이트 시각·원본 rank를 만들지 않는다.
- 실제 2026-10-10 TJ/KY×3기간 6개 조회 HTTP200/각100곡, 반환 brand 일치, 집계 날짜 필드 미제공 확인. 원문은 저장하지 않고 시간·키·해시·수치만 기록했다. 100곡 수는 고정 규칙으로 사용하지 않는다. 호출 성공은 최신성·실제 기간 차이·저장 허용의 증거가 아니다.
- 공식 출처: https://api.manana.kr/karaoke/popular/joysound/daily 및 https://api.manana.kr/ (2026-10-10 확인). FAQ 무료 표시는 상업적 저장·재배포·캐시 범위의 별도 확인을 대체하지 않는다. D12대로 운영 수집·실데이터 저장은 미활성, 개발 fixture만 후속 연결한다.
- 실행: services/api/gradlew.bat -p services/api test bootJar --console plain 및 로컬 read-only 출처 probe. 전체 645개: 565 성공/80 MySQL 제외/실패0. bootJar PASS. 실제 MySQL은 필요한 원격 CI에서 확인한다.
- 현재 모델 직접 검토: D12·실제 출처·기존 V7 스키마 브랜드/period/source check·6개 범위·잘못된 값·Locale·데이터 비추정 대조. 지적 없음. 서버 기간 계약 작업으로 별도 폰 실기 불필요; 화면 실기는 P16-06/08에서 계획한다. 요청 6.1 Sol/medium 유지.
- 변경 파일: services/api/.../charts/ChartScope.java, ChartScopeTests.java. 기존 schema/API/개인 데이터는 변경하지 않았다. P16 목록의 옛 연월 설명도 확정 D12 기준으로 정정했다.

## 최종 완료
- 최종 SHA 5b6b20ae52414fdc3b13db30c449c8d15630f0b9, 필수 CI 38013537478, 38013537474 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
