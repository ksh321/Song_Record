# WORKFLOW-01 개발 자동화 초기 점검

- 확인일: 2026-09-29, Windows 사용자 환경 및 Codex 격리 환경을 구분해 점검.
- 기준 코드: `9b2fc86bc08ef013da320292b750f706e5c80c89`, main. 최초 작업 트리 clean,
  staged/unstaged/untracked 사용자 변경 없음. origin/main도 같은 SHA 확인.
- 요구사항: 이번 요청 WORKFLOW-01, 기존 R002/R035/R036/R037 및 P01-08·P10-01·P10-02.
- 범위: 규칙·출처 색인·진행 감사·실행/검증 스크립트. 앱/서버 기능·DB·원본 자료 수정 없음.
- 판정: 자동화 로컬 검증 확인. 초기 설정 전체는 속도 적용·USB·Docker·보호 규칙 확인 대기.
  새 변경 커밋/CI 증거는 이 문서의 후속 기록과 Git history로 연결한다.

## 원본과 경로

실제 외부 폴더는 `C:/Users/shoon111111/Desktop/source`이며 6개 파일이 있다.
기존 저장소의 5개 reference 원본과 계획서 DOCX를 재사용했다. Word 문단/표를 텍스트로
추출하고 231개 작업을 색인했다. 두 DOCX의 원본 바이트는 동일하다.
텍스트는 LF 정규화 후 동일하며 HTML 저장소 체크아웃은 CRLF 1,397개, 외부 원본은 LF다.
이는 정책 차이가 아니다. 역할 TXT의 원본도 줄바꿈 정규화 해시와 raw 해시가 다르다.

| 외부 원본 | raw SHA-256 |
|---|---|
| 코드 구현 참고 사항 (1).txt | `9f6a8df4f0908e61ca8a3612b83f4f26610ccdb0cec5165a541a73cb72bf10bd` |
| 노래기록앱_구현설계서_v1.11(1).docx | `957786385b081e52cdca2f83250b712701bcb63a73df63df47c1983a5916fe36` |
| 노래기록앱_코드구현계획서_v1.0(1).docx | `d3da465095024712634dee18fa341ce500dabbf78a72e37b546498b2e8bfe0bd` |
| b-playlist-ui-v1.11(1).html | `3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555` |
| UI_REFERENCE(2)(1).md | `b62babdba6a124277e57e57b56a605325cd961e4040c73cca8a9c03a96a53d17` |
| ui_reference_palette(2)(1).json | `88ad5972f79424629b87698760ca98894c4f65fc23d9448bcec1effc4d12d83b` |

설계의 계정별 저장·정보와 파일 분리·트랜잭션·승인 후 완료·삭제 UUID 보존과 계획의 선행 조건,
HTML의 샘플과 제품 기능 구분, UI 조작 규칙, 팔레트의 초기 blue/녹음 red 규칙을 확인했다.
원본 정책 변경 없음. D12 차트는 명시적 승인 기록을 확인했다. D06 컨디션 고정 계약과
P09-07b 사용자 정의 컨디션 API는 충돌하므로 별도 승인 근거 확인 전 변경하지 않는다.

## 코드와 기존 기록 대조

| 범위 | 실제 확인 | 판정/남은 일 |
|---|---|---|
| P00~P05 | requirements/decisions, 앱 골격/UI, 이전 verification 존재 | 과거 완료 기록 보존. 실기를 이번에 재실행했다고 주장하지 않음 |
| P06 | 서버 auth와 Flutter auth_adapters, 계정 분리 코드/테스트 존재 | P06-06/08 실기 결과가 저장소 문서에서 미완료. 로그인·계정 전환 완료로 재판정하지 않음 |
| P07 | API 계약, 소유권·멱등·revision·jobs 코드/테스트 | 현재 SHA의 서버/계약/MySQL CI 성공. 운영 검증은 아님 |
| P08 | songs API·통합 테스트, `1c1818b`까지 작업 이력 | 현재 SHA의 자동 회귀 성공. 제품 화면 전체 통합과 별개 |
| P09 | recordings·tags·conditions 및 테스트, V15 마이그레이션, `1d487b5` | 자동 CI 성공. D06 충돌 및 모바일 컨디션 연결 확인 대기 |
| P10-01 | LocalRepository·AccountStore 원자 저장, `2837c38` | 현재 코드/관련 테스트 확인 |
| P10-02a | DependencyPlanner·dispatchSnapshot·localOrder, `9b2fc86` | 후보/대기 판정 구현, 로컬 19개 테스트 및 기존 CI 성공. HTTP/ACK 없음 |
| P10-02b 이후 | P10-02a 문서에서 후속 송신 명시 | 미착수. 계획에 적혀 있다는 이유로 완료 처리하지 않음 |

README 첫 진행 요약은 P04-08, progress.md 현재 절은 P05-08에 머물렀다. 최신 감사 요약을
그 문서들에 통합하고 과거 상세 기록은 역사로 보존한다. 최신 코드의 모든 작업을 완료로 올리지 않는다.

## 환경과 실행 증거

아래 명령은 저장소 루트 기준이며 Python은 번들 Python을 사용했다.
대상은 기준 코드 `9b2fc86` 위 WORKFLOW-01 미커밋 변경이다. 제품 코드는 동일하다.

| 명령/점검 | 실제 결과 |
|---|---|
| `git status --short`, `git log`, `git ls-remote origin refs/heads/main` | clean main, 로컬/원격 `9b2fc86` 일치 |
| `codex --version`, `codex login status` | 0.155.0-alpha.9.2, Logged in using ChatGPT |
| `flutter --version` | 3.47.4 / Dart 3.13.3, revision 9584c6713b |
| `java -version` | Temurin 21.0.12.1+1 |
| Docker 버전/엔진 | 클라이언트 29.8.0, Compose 5.5.1. 엔진 pipe 없음: 실행 검증 대기 |
| Android Studio 파일/adb | 설치 파일 존재. adb 시작 성공, 연결 기기 0개. IDE 실행/USB 실기 대기 |
| `flutter doctor -v` | Android SDK 36.0.0·Android toolchain 정상, 라이선스 모두 승인. Android용 JBR 21.0.10. Windows 데스크톱용 Visual Studio 없음은 이번 Android 범위 밖이라 설치하지 않음 |
| GitHub CLI | PATH에서 찾지 못함. 설치하지 않고 기존 GCM 인증 사용 |
| `python tools/index_sources.py --source <외부경로>` 및 `--check` | 6개 원본 대응·색인 통과, 231개 고유 작업 |
| `pwsh -NoProfile -File tools/workflow.ps1 -Mode Quick` | 색인/실패 경로 unittest/공백 검사 성공 |
| PowerShell Parser로 `tools/*.ps1` 확인 | 문법 오류 0 |
| 최초 Mobile 분석 `--no-pub` | 14 issues: 오래된 로컬 package config에서 인증 패키지 누락. 통과 처리하지 않음 |
| `flutter pub get --enforce-lockfile` (apps/mobile) | 성공. 잠금 버전 유지, 앱 코드/lockfile 변경 없음 |
| Mobile 재실행 | flutter analyze 문제 없음, 동기화 테스트 19개 전체 통과 |
| 로컬 서버 전체/DB/APK 빌드 | 이번 문서/스크립트 변경에 불필요해 미실행. 기존 정확한 SHA의 CI 증거 사용 |
| `github-check.ps1 -Commit 9b2fc86... -InspectPolicy -Account ksh321` | 기존 3개 workflow와 그 job success, 새 Development workflow 미존재는 PENDING/exit 2 |

최초 격리 Git은 소유자 차이로 실패했다. 해당 저장소만 명령별 safe.directory로 읽고,
사용자 환경에서도 clean을 확인했다. 전역 safe.directory 설정은 바꾸지 않았다.
GitHub 비인증 조회 404 → GCM 인증으로 private 저장소 확인. 계정 2개 때문에 비대화형
선택 실패 → 확인된 ksh321 지정. repo 조회 URL 끝 slash 오류는 제거하고 정상 조회했다.
브랜치 protection/rules는 인증 후에도 HTTP 403: 보호 없음으로 해석하지 않는다.

기준 SHA의 원격 증거:
[CI 36430037072](https://github.com/ksh321/Song_Record/actions/runs/36430037072),
[API contract 36430037008](https://github.com/ksh321/Song_Record/actions/runs/36430037008),
[Idempotency MySQL 36430037215](https://github.com/ksh321/Song_Record/actions/runs/36430037215).

## 에이전트 적용 증거

- 마스터 현재 모델/추론/속도는 도구에서 확정할 수 없어 변경·적용 완료로 보고하지 않는다.
- 독립 상태 작업자: Luna/medium. 단순 코드/기록 대조이므로 선택. CLI 헤더에서 모델/추론 확인.
  첫 읽기 전용 쉘은 정책 거절되어 검증 실패로 기록했다. 두 번째는 소스/문서 입력을 받아
  P10-02a의 HTTP/ACK 미구현, 다음 P10-02b, 오래된 기록을 독립 대조했다.
- worker session: `01a0ebdb-5e6b-75e1-97a2-db07c7df889e`.
- `--strict-config`, ChatGPT 강제 로그인, service_tier default, features.fast_mode false 요청은
  CLI가 수락했다. 실제 처리 tier telemetry는 없어 Standard 적용 확정은 대기다.
- 별도 검수자는 자격 증명·완료 판정의 위험을 고려해 Astra/high로 선정한다. 결과는 후속 절에 기록.
- 원본 자료/검토 프롬프트/응답은 외부 유료 API로 전송하지 않고 구독 Codex CLI만 사용했다.

### 별도 검수 1과 수정

Astra/high session `01a0ebe5-ac1e-7e93-a577-ae11b9d21e7c`가 제공 소스만 읽고 검수했다.
별도 쉘 실행 성공으로 오인하지 않는다. CLI 헤더의 모델/추론은 확인했고 실제 tier는 미확인이다.

- 보호 조회 403을 전체 대기(exit 2)로 반영. CI 결과와 정책 결과를 분리했다.
- workflow 표시 이름 대신 실제 파일 경로·필수 job을 대조하고 run/job 페이지 전체를 수집한다.
- Doctor가 ChatGPT 로그인 문구를 확인하며 API 로그인/알 수 없는 출력은 통과시키지 않는다.
- 실행 결과는 working_tree 범위와 시작/종료 Git 변경, 전체 상태·예외를 기록한다.
  실행별 raw 로그를 고유 폴더에 남겨 실패 이력을 다음 실행으로 덮어쓰지 않는다.
- USB 판별은 Windows에서 누락될 수 있는 `usb:` 표시 대신 `adb -d get-serialno`를 쓴다.
  여러 USB 기기/미승인/기기 없음은 대기. 실제 USB 전송·reverse는 연결 전까지 검증 대기다.
- 승인된 원본 해시를 고정해 외부 경로 없이 재생성해도 바뀐 원본을 자동 승인하지 않는다.
- Python 3개 테스트와 PowerShell 21개 검사로 API 인증 거절, 알 수 없는 인증, 누락/진행 CI,
  필수 job 누락, 101번째 skipped job, 정책 미확인, 예외 보고, USB 모호성을 검증했다.
  이 테스트는 판정 로직 검증이며 실제 휴대폰·101개 GitHub job을 실행한 증거가 아니다.
- `git check-ignore`로 로컬 프롬프트/JSON 제외를 확인했다. 앱·서버·infra·기존 원본 diff 없음.

### 별도 검수 2

수정한 staged 변경 전체(생성 자료는 generator·manifest·정합성 증거로 대조)를 새 Astra/high
검수자가 읽었다. 추가 차단 결함 없음으로 WORKFLOW-01 변경 범위를 승인했다.
모델은 실제 실행을 직접 확인했다고 주장하지 않았으며 새 SHA CI·보호 규칙·Docker·USB·실제
tier 확인은 외부 게이트로 유지했다. 결과는 `.local/workflow/Reviewer-20260929-154916-638.md`다.
최종 확인에서 외부 원본 6개 비교 PASS, 기존 원본 6개와 apps/services/infra staged diff 없음,
비밀 파일/로컬 기록 경로 stage 0개를 확인했다.

## 다음 작업과 재개 조건

다음 구현 ID는 **P10-02b**다. 계획서 `[p00578]~[p00580]`의 P10-02 완료 기준을 유지하는
a/b 분할이며 R002/R035/R036/R037에 연결된다. 이유는 큐 저장·후보 판정이 실제 코드와 테스트로
확인되었고, 실제 HTTP 송신과 승인 후 원자 반영이 아직 없기 때문이다.

착수 전 D06/P09-07b의 컨디션 정책 및 서버 CONDITION과 로컬 RECORDING_CONDITION 매핑을
확인한다. 계정 lease·요청 불변성·op_id·baseline·원자 ACK의 실패 경로부터 설계한다.
P06 필수 실기 증거가 없는 상태에서 인증 포함 동기화 통합 완료를 선언하지 않는다.
현재 독립적으로 진행 가능한 것은 정책 근거 조사와 송신 계약/테스트 설계다.

휴대폰 테스트 필요 시 USB 연결·잠금 해제·디버깅 승인을 알리고 녹음/청취는 사용자 확인으로
남긴다. Docker 엔진 준비 전 DB 검사는 대기다. 기존 데이터 삭제·초기화는 하지 않는다.
