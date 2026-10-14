# P25-01 정적 분석과 빌드

원본 계획 p01071–01072, R005. 사용자 P25 전체 원수 승인, 현재 관측/요청 gpt-6.1-sol medium. 시작 기준 로컬/원격 main bb8691f9017e65af3550504028fe8d353a8b3504 일치. 기존 변경·완료 이력 보존, 내 할 일은 원본 P25-01–08로 전환.

## 변경과 근거

- `.gitattributes`: 해시를 갖는 fixture JSON과 계약/결정 Markdown을 LF로 고정한다. Word 원본·미디어 바이너리는 바꾸지 않는다. 실제 CRLF→LF 결과를 Git HEAD와 바이트 대조해 내용 불변 확인. fixture 18개는 본문 변경 없음.
- `fixtures/index.json`: 이미 커밋된 D01·D12 개정과 다른 참조 해시2개를 현재 LF 문서의 SHA256으로 갱신. 케이스/기대값·앱/서버 로직·제공자 허가 상태를 바꾸지 않음. 이전/현재 해시와 근거는 보호된 source-hash-changes.json 및 Git diff에 보존.
- 실패 분리: 최초 fixture JSON CRLF, 해당 보완 뒤 계약 문서 CRLF로 다음 참조 실패(같은 checkout 원인). 계약 LF 보존 확인 중 별개로 D01/D12 오래된 참조 해시 발견. 최종 보완 후 기존 엄격한 validator 통과. 기능 수정 실패와 서로 다른 근본 원인을 합산하지 않음.

## 실제 일괄 검사

로컬 run-checks.py의 계획/명령/시각/원시 로그는 Git 제외 P25-01 디렉터리에 보존한다. 원본 해시 → fixture → Drift 생성/스키마 → 앱 분석/전체 테스트/APK → 서버 clean build → API 계약 → 삭제 웹 → diff 순서로 한 명령에서 실행하고 첫 실패에 멈췄다. 초기 단서 수정 전 전체 검사를 반복하지 않음.

- 원본6개/검색 색인 PASS. fixture169개, 순수 평가31개·미디어3개 PASS. 나머지 integration specification138개는 이 도구에서 미실행이며 통과 실적으로 세지 않음.
- Drift 코드·스키마 생성 PASS, 추적 생성물 diff 없음. Flutter analyze PASS. 전체 앱 테스트1,204 PASS, 건너뜀0. 실제 dev debug APK build PASS.
- 추가 재현 확인: offline/enforce-lockfile pub get PASS, lockfile/생성물 불변. 의존성/SDK 버전을 바꾸거나 새 유료 도구를 사용하지 않음.
- 서버 clean build PASS. JUnit772개 중683개 실행 PASS·실제 MySQL 조건 등89개 건너뜀, 실패0. P25-02에서 실제 MySQL 필수 검증을 따로 수행해야 하며 서버 필수 검증 전체 완료라고 하지 않음.
- OpenAPI·로컬 참조·security·wire7개·schema boundary143개 PASS. 삭제 웹6개 PASS/skip0. diff check PASS.

## 현재 모델 별도 검토

실제 diff는 해시2개와 checkout 규칙만이다. Git 원본과 현재 참조의 대응·미디어 불변·원본6개 보존·케이스 기대값 유지·생성물 불변·전체 검사 결과를 대조했다. main → LoginGate → SongRecordApp의 실제 Repository/동기화/업로드/곡/녹음/목록/설정/백업 연결과 production 소스의 TODO/UnimplementedError/UnsupportedError 검색을 확인했다. 이 범위의 미연결 임시 구현은 발견하지 않았다. 별도 에이전트/추가 모델 호출 없음.

공개 OAuth·운영 worker·실제 출시 서명·개인정보/삭제 공개 URL·두 제조사 실기·베타 관찰은 뒤 P25의 실제 완료 조건이며 정적 빌드 성공으로 통과시킬 수 없다. 기존 P00–P24 기록과 D12 무료 범위의 조건 확인 유예를 보존하고 전체 출시 완료를 주장하지 않는다.

현재 로컬 검사/검토 완료, 정확 SHA 커밋·푸시·필수 CI 대기. 다음 P25-02, 현재 직접 사용자 행동0건.

학습 개념: JSON 의미가 같아도 바이트 해시는 CRLF/LF에 따라 달라진다. 바이트 규칙을 고정하고 개정된 근거의 참조 해시를 추적해야 엄격한 검사를 유지할 수 있다. 건너뛴 테스트는 통과가 아니다.
