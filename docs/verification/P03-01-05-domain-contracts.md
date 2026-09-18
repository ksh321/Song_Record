# P03-01~05 공통 도메인 계약 검증

## 범위

- `SongId`, `RecordingId`, `TjNumber` 타입 분리
- UUID 문자열과 16바이트 표현의 왕복, unsigned 바이트 순서
- 버전·키·곡 티어·녹음 티어 타입과 사용자 표시
- 로컬·메타데이터·동기화·클라우드·차단 원인·수명 상태 분리
- 입력 길이, 계약 공백, 메모 줄바꿈 정규화

## 자동 검증

- Flutter `domain_contract_test.dart`가 앱의 식별자·표시·상태 타입과 `fixtures/contracts/input.json` 전체 사례를 검사한다.
- Spring `DomainContractsTests`가 서버의 같은 규칙과 같은 fixture 11개 사례를 검사한다.
- CI의 Flutter analyze/test/APK build와 Spring clean build가 두 구현의 컴파일 및 회귀 테스트를 실행한다.

## 완료 기준

- 앱과 서버에서 같은 입력의 `actual` 코드 포인트 수와 유효성 결과가 일치한다.
- TJ 번호 `00123`은 `123`으로 바뀌지 않는다.
- 곡 ID와 녹음 ID는 별도 타입이며 UUID는 16바이트로 왕복된다.
- 원키·성별 키·미정·티어 표시가 설계 계약과 일치한다.

P03-06~08의 녹음 스냅샷, 기본값/dirty 규칙, 정렬·선택 함수는 후속 범위다.
