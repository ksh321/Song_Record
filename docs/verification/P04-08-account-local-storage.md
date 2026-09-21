# P04-08 계정별 로컬 저장 구조 검증

2026-09-21. 시작 커밋 `7212fec569cc7691dca978650ac202cc1c09004a`. P04-07은 [GitHub CI 35596556685](https://github.com/ksh321/Song_Record/actions/runs/35596556685)에서 MySQL 마이그레이션·제약, Spring Boot 빌드·테스트, Flutter 분석·테스트·Android APK 작업 모두 성공했다.

P04-08 상태: **구현 및 제한된 로컬 검증 완료 / 커밋·push·기본 네이티브 SQLite와 Android CI 확인 대기**. 서버 V1~V7, 사용자 개발 DB, 기존 녹음, 원본 설계 문서는 수정하지 않았다. Flutter UI/인증/녹음 서비스에는 아직 연결하지 않았다.

## 변경과 구현 경계

[D01](../decisions/D01-implementation-stack.md)의 Drift/SQLite를 사용한다. `pubspec.yaml`·`pubspec.lock`에 Drift/drift_dev 2.35.0, sqlite3 3.5.2 및 코드 생성 도구를 추가했다. `build.yaml`, 생성 Dart 코드, `drift_schemas/account/drift_schema_v1.json`을 관리하고 CI에서 재생성/스키마 일치를 검사한다. 생성 파일을 수동 수정하지 않는다.

모바일 `.gitattributes`는 생성 코드와 스키마 보존본의 줄바꿈을 LF로 고정한다. Windows checkout의 CRLF 변환만으로 Drift의 보존본 비교가 실패하지 않게 하는 제한된 설정이다.

| 저장 구조 | 이번 역할 |
|---|---|
| local_account | 단일 불변 소유 계정과 dev/staging/prod 환경. 열 때 기대 값과 비교 |
| metadata_copies | 개인 업무 자료의 서버 revision/본문과 로컬 초안 분리. 공용 차트·인증 토큰은 대상 아님 |
| local_mutations | op_id·기준 revision/본문·변경 내용·로컬 요청 해시·대기/충돌/재시도 상태·서버 응답 |
| local_recording_files | 계정/녹음별 상대 경로·해시·크기·상태·검증 시각·cleanup_fence |
| recording_journals | 같은 계정의 파일과 연결된 작업 UUID·임시/최종 경로·녹음 단계·복구 메모·revision |
| import_jobs / import_items | 같은 계정 백업의 가져오기 작업·항목·중단/재개 상태. 실제 ZIP 파싱/복사기는 아님 |
| sync_cursors | 적용 확인된 change_seq, 기준 데이터 확보 여부, 스냅샷 재개 위치. 최초 cursor는 NULL |

현재 업무 사본은 허용된 엔터티별 JSON 객체로 보관한다. SQLite는 계정 FK·엔터티 코드·JSON 객체·revision/본문 관계를 검사한다. 각 엔터티 내부의 필수 업무 필드와 연결 관계를 전부 검증하는 대체 도메인 모델은 아니다. P10에서 서버 DTO의 필드 허용 목록과 개인 자료 소유권 검사를 거쳐 넣어야 한다. `user_id`가 있는 로컬 편집은 활성 계정과 일치해야 한다.

### 계정과 파일 분리

- 앱 전용 지원 디렉터리 아래 `song_record/<environment>/accounts/<canonical UUID>/`로 나눈다. 빈 UUID/잘못된 UUID를 계정으로 사용하지 않는다.
- `AccountStoreManager` 한 개가 직렬로 DB를 열고 닫는다. 인증된 계정을 P06이 제공해야 하며 저장 모듈이 임의 UUID의 인증을 수행하지 않는다.
- 계정 전환/로그아웃 호출 즉시 세션 세대 번호를 변경한다. 이전 계정의 대기 작업과 늦게 도착한 결과는 거절한다. 이미 실행 중인 A 쓰기는 A의 DB에서 끝날 수 있지만 B 저장소로 향하지 않으며 B에는 결과를 전달하지 않는다.
- 로그아웃은 DB 연결을 닫을 뿐 원본·미전송 변경·journal·가져오기 작업을 삭제하지 않는다. 같은 계정으로 다시 열면 남은 정보를 읽는다.
- DB 파일 내부의 소유자/환경을 검사하므로 다른 계정 DB를 복사해서 경로만 바꾼 경우에도 열기를 거절한다. 오류 시 원본 파일을 초기화하지 않는다.
- 고정된 `audio/<recording UUID>.m4a`, `pending/<recording UUID>.m4a.part`, `imports/<job UUID>.zip`만 허용한다. 외부 URL·서버 object key·절대 경로·상위 경로 이동·링크를 거절하고 DB 보조 파일(WAL/SHM/journal)도 점검한다.
- 완료된 로컬 음성은 최종 경로에 실제 존재하고 크기 1~6MiB와 SHA-256이 맞아야 등록/읽기가 된다. `SAVED` UUID의 내용 교체를 거절한다. 파일의 유효한 M4A·코덱·재생 시간 검사는 P18/네이티브 계층 범위다.

이는 앱 내부 접근 경계다. DB 암호화나 루팅/기기 관리자 공격·OS 백업 정책을 완성했다는 뜻은 아니다. 임의 SQL/파일 접근 권한을 가진 코드에는 저수준 모듈을 제공하지 않고 앱 UI는 scoped store를 사용해야 한다.

### 데이터 보존

- 로컬 초안과 LocalMutation을 한 트랜잭션에 저장한다. 대기열 저장을 강제로 실패시키는 시험에서 초안도 남지 않는 것을 확인했다.
- 같은 op_id와 같은 내용은 재시도로 처리한다. 오래된 요청 재시도가 더 최근 초안을 되돌리지 않는다. 같은 op_id의 다른 내용은 거절한다.
- 기준 revision/본문과 요청 본문은 재시도 중 불변이고 시도 횟수는 줄일 수 없다. 원래 서버 본문·최신 서버 응답·로컬 초안을 따로 남겨 충돌 판단에 사용한다. 실제 전송·ACK/재시도 스케줄·충돌 해결은 P10 범위다.
- 파일 메타정보와 journal, ImportJob과 항목들은 각각 같은 트랜잭션이다. DB 트랜잭션과 실제 파일 쓰기/이름 변경이 한 원자적 작업이 되는 것은 아니며 P18에서 journal 기반 복구를 연결해야 한다.
- 마지막 적용 cursor의 역행/NULL 초기화를 거절한다. 스냅샷을 몇 번째 페이지까지 받았다는 메모만으로 적용 cursor를 올리지 않는다. 완전한 사본 교체와 cursor 원자적 전진은 P10이다.
- 스키마 v1만 지원한다. 미지원 버전/미래 버전이면 명시적 오류로 멈추고 DB를 삭제하거나 재생성하지 않는다. 향후 보존 마이그레이션과 재시작 시험은 P04-09다.

## 실제 실행 환경과 결과

원본 프로젝트의 Windows 도구 캐시/생성 폴더 접근 제한과 SQLite 기본 바이너리의 네트워크 다운로드 실패로 앱과 공통 fixtures를 별도 작업 폴더에 복사해 검증했다. 기존 캐시나 사용자 자료는 지우지 않았다.

- Flutter 3.47.4 / Dart 3.13.3 / Drift 2.35.0 / sqlite3 Dart 패키지 3.5.2.
- 잠금 파일로 해결된 패키지를 전용 시험 캐시에 복사하고 `pub get --offline --enforce-lockfile` 성공.
- **시험 복사본의 pubspec에만** sqlite3 공식 hook의 `source: system`, `name_windows: winsqlite3`를 사용. Windows 시스템 SQLite 런타임은 **3.51.1**로 확인했다. 저장소 pubspec에는 이 override를 넣지 않았다.
- 저장소/Android는 패키지의 기본 번들 바이너리와 해시 검증을 유지한다. 다운로드 제한을 우회하려 TLS 검증을 끄거나 검증되지 않은 바이너리를 받지 않았다.
- 합성 UUID·작은 가짜 파일만 사용한다. 실제 음성 녹음이나 사용자 계정/DB는 시험에 포함하지 않는다. 각 테스트가 만든 고유 임시 폴더만 경계 확인 후 제거한다.

| 검사 | 결과 |
|---|---|
| `flutter analyze` | 문제 없음 |
| `flutter test --reporter expanded` | 57개 통과, 1개 보류 |
| 새 `account_store_test.dart` | 27개 통과, Windows 링크 생성 권한 부족으로 1개 보류 |
| 기존 앱 테스트 | 기존 30개 통과 |
| Drift 코드 생성 / v1 스키마 내보내기 | 성공 |
| Windows 테스트의 기본 번들 SQLite 바이너리 | 다운로드 불가, 시스템 SQLite로만 시험함 |
| P04-08 기본 설정 GitHub CI·Android APK·기기 실기 | 아직 미실행 |
| 서버/MySQL 회귀 | P04-07 CI 성공을 확인. 이번 서버 코드 변경 없음, 이번 로컬 재실행 없음 |

새 검사에는 A/B 동일 리소스 UUID 분리, dev/prod 분리, 이전 세션 거절, 타 계정 DB 복사 거절, 버전 99 DB 거절 후 원본 보존, 트랜잭션 롤백, op_id 재시도 불변, 기준/로컬/서버 충돌 본문 보존, cursor·가져오기 진행·journal·음성의 새 DB 연결 후 유지, 경로/객체 키 거절, 파일 크기/해시/누락 확인이 포함된다. 재열기는 새 manager/연결 수준이며 실제 Android 프로세스 강제 종료·재기동 검증을 대신하지 않는다.

Windows에서 보류한 링크 시험은 Ubuntu에서 링크를 실제로 생성하고 접근 거절을 확인한다. Linux에서 링크 생성 실패를 보류 처리하지 않는다. 새 CI 성공 전 해당 검사를 통과한 것으로 기록하지 않는다.

처음 실행 때 DB isolate 설정 콜백이 manager의 Future 대기열까지 캡처해 열기에 실패했다. 콜백 생성 위치를 최상위 함수로 옮겨 전달할 값만 캡처하게 수정했고 실제 백그라운드 DB 열기/재열기 검사를 통과했다. 예외 검사는 백그라운드에서 전달된 원래 오류 메시지까지 확인한다.

## 재실행과 다음 단계

일반 개발 환경에서 `apps/mobile`의 [실행 안내](../../apps/mobile/README.md#p04-08-계정별-로컬-저장-기반)를 따른다. 시험용 시스템 SQLite 설정을 운영 pubspec에 옮기지 않는다. CI는 잠금 의존성 설치 → Drift 재생성/보존본 일치 → analyze → 전체 test → dev APK 순서로 수행한다.

1. P04-08 커밋·push 후 기본 구성 CI와 Ubuntu 링크 검사 결과 확인.
2. P04-09: 빈 DB/증분 업그레이드·기존 데이터 보존·재시작 검증. 기존 v1 보존본을 임의로 덮어쓰지 않는다.
3. P06/P10/P18/P22: 인증된 계정 수명주기, 동기화 적용/전송, 네이티브 녹음 journal/파일 복구, 실제 ZIP 가져오기 연결.

P02의 `prototype_device` SharedPreferences journal과 기존 음성을 자동 이동·삭제하지 않는다. 소유자를 임의 추정하지 말고 인증과 검증된 이전 절차를 마련한 뒤 연결해야 한다.

이번에도 `.git` 쓰기 권한 요청 후 `git add`에서 `index.lock: Permission denied`가 발생했다. 파일은 로컬에 보존했고 원격만 따로 커밋하는 방식은 사용하지 않았다. GitHub Desktop에서 이번 변경 20개 파일 전체를 확인해 `feat(mobile): add account-scoped local storage`로 커밋하고 Push origin을 눌러야 한다. 일부 코드만 선택하지 말고 생성 스키마·CI·설명 문서도 함께 포함한다.

설정 근거: [Drift 시작하기](https://drift.simonbinder.eu/setup/), [네이티브 DB](https://drift.simonbinder.eu/platforms/vm/), [트랜잭션](https://drift.simonbinder.eu/dart_api/transactions/), [마이그레이션](https://drift.simonbinder.eu/migrations/). SQLite hook은 잠금 버전 sqlite3 3.5.2의 공식 `doc/hook.md`를 확인했다.
