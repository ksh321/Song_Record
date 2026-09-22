# P04-09 DB 검증 — 검증 완료

2026-09-22. 기준 커밋은 직전 사용자 Git 출력의 `db1ef62e5cc06c37b0660239ae843a4e12913f82`다.
계획서 P04-09의 빈 DB 설치·증분 변경·잘못된 관계 거절·TJ 번호 경쟁·앱 재기동과
데이터 보존을 실제 MySQL 및 Android 로컬 DB에서 확인했다. 아래 결과는 사용자 PC와
기기에서 제공한 실행 출력에 근거한다. 검증 보조 파일·문서의 커밋·push는 별도 마무리 단계다.

## 서버 MySQL: 사용자 Windows PC에서 통과

사용자가 Python 3.14.0, Java 21.0.12.1, Docker 29.8.0 / Compose 5.5.1 환경에서
`services/api/gradlew.bat bootJar` 성공 후 `infra/scripts/verify_p04_disposable.py`를 실행했다.
완성된 실행 출력에서 다음 결과를 확인했다.

| 검사 | 결과 |
|---|---|
| P04-01~03 계정·곡·녹음 제약 및 V1 데이터 보존 | 통과 |
| P04-04 목록·분류·동시 접근 | 63개 통과 |
| P04-05 보관·용량·증분 데이터 보존 | 72개 통과 |
| P04-06 동기화·삭제 작업·트랜잭션 | 88개 통과 |
| P04-07 차트·스냅샷·용량 경쟁 | 86개 통과 |
| V1→V2→V4→V5→V6→V7 변경 및 동일 DB 서버 재기동 | 통과 |
| 검증 전용 컨테이너·볼륨·네트워크 정리 | 통과 |

최종 출력은 `P04-01~07 upgrade, constraints and restart verification passed.` 및
`MySQL regression: PASS; cleanup: PASS`다. `Rejected as expected`와 `PASS reject`는
잘못된 관계·값·중복 작업이 예상 MySQL 오류로 거절됐다는 성공 결과다.

- 테스트 프로젝트: `song-record-p0409-ffa05756570d2485`
- MySQL/API 테스트 포트: 63092 / 63093
- 사용자 PC 증거 폴더: `%TEMP%/song-record-p0409-ttnf86y7`
- 증거 파일: `result.json`, `verification.log`
- DB는 매 실행 새 Compose 프로젝트의 새 볼륨에 생성했다. 개발용 `infra/.env`를 가져오지 않는다.
- 실행 보조 코드의 모의 검사와 실제 MySQL 실행은 별개다. 위 표는 사용자가 제공한 실제 MySQL 출력에 근거한다.

P04-08이 포함된 기존 [CI 35600881401](https://github.com/ksh321/Song_Record/actions/runs/35600881401)는
앞선 원격 확인에서 성공했다. Flutter 분석·58개 테스트·Drift 생성물 일치·Android APK 빌드,
Spring Boot 빌드/테스트, MySQL 검증이 포함됐다. [P04-08 보고서](P04-08-account-local-storage.md)의
업로드·CI 대기 상태도 이 후속 결과로 해소했다. 해당 CI는 기준 커밋의 결과이며 이번에 추가한
P04-09 검증 보조 파일의 새 CI 실행 결과를 의미하지 않는다.

## Android 로컬 DB: 실제 다른 프로세스에서 재실행 통과

사용자가 검증 파일을 `dart format`한 뒤 `flutter analyze`에서 `No issues found!`를 확인했다.
SM A546S / Android 16 (API 36), 기기 ID `R5CW618VA1M`에서 seed와 재실행 결과를 제공했다.

| 증거 | 확인 값 |
|---|---|
| 동일한 검증 실행 ID | `d41a074e439899d5bb41edf1a5bbaec0` |
| 저장 프로세스 → 재실행 프로세스 | `23144` → `23742` |
| 최초 저장 | 두 계정의 빈 DB 생성, `SEEDED`, DB 연결 열린 상태 |
| 재실행 | 기존 DB 파일 두 개 존재, 서로 다른 Android PID 확인 |
| 보존 | A/B 초안·서버 revision/상태·요청·합성 파일 크기/해시·journal·snapshot·cursor·가져오기, A 서버 사본·충돌 응답 |
| 계정 경계 | 이전 세션 거절, 동일 UUID의 A/B 데이터 분리, A 복귀 후 유지 |
| 부분 진행 | 가져오기 1/2, APPLIED/PENDING 항목 상태 유지 |
| 스키마 | 로컬 v1 유지 |
| 최종 출력 | `ANDROID STORAGE RESTART: PASS` |

위 결과는 사용자 실기 출력에서 확인했다. 실제 실행한 종료 명령의 터미널 출력은 별도로 받지
않았으며, 앱 프로세스가 실제로 교체됐다는 근거는 두 PID와 동일한 실행 ID다.

`apps/mobile/tool/verify_account_storage_android.dart`는 제품 화면과 별도로 실행하는
Android debug/dev 검증 진입점이다. 새 의존성 없이 실제 `AccountStoreManager`,
`AccountDatabase`, `AccountPaths`를 사용한다.

- `getApplicationSupportDirectory()/p04_09_storage_verification/<무작위 실행 ID>` 아래에
  합성 계정 A/B와 합성 파일을 생성한다. 평소 계정 DB 경로와 P02 녹음 journal을 사용하지 않는다.
- 두 계정이 같은 곡·파일·작업 UUID를 사용하되 본문과 파일 바이트는 다르게 만든다.
- A에는 충돌 요청, 최신 요청, 서버 사본, cursor 42, snapshot 재개 정보,
  가져오기 진행 1/2와 녹음 journal을 남긴다. 동기화·가져오기 진행 값은 fixture SQL로 주입한다.
- 마지막 변경을 커밋한 뒤 A의 백그라운드 DB 연결을 열린 상태로 유지한다.
- `SEEDED` 이후 Android `am force-stop`으로 종료하고 같은 설치 앱을 다시 실행한다.
- 저장 때의 Android PID와 재실행 PID가 달라야 한다. Hot Restart는 통과로 처리하지 않는다.
- 재실행에서는 기존 파일 존재, 계정별 초안·요청·충돌·cursor·journal·가져오기·파일 해시,
  계정 전환 뒤 이전 세션 거절과 계정 A 복귀 시 데이터 분리를 확인한다.
- 합성 바이트 보존 검사이며 실제 AAC 녹음·디코딩·재생 검사가 아니다.
- 검사 결과는 probe 전용 루트의 `last_result.json`에 남긴다.

첫 실행:

```powershell
cd apps/mobile
dart format tool/verify_account_storage_android.dart
flutter analyze
flutter run --flavor dev --dart-define=APP_ENV=dev -t tool/verify_account_storage_android.dart
```

`SEEDED`가 표시된 뒤 별도 PowerShell에서 연결된 해당 기기를 지정해 수행한다.

```powershell
$probeAdb = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
& $probeAdb -s R5CW618VA1M shell pidof com.ksh321.songrecord.dev
& $probeAdb -s R5CW618VA1M shell am force-stop com.ksh321.songrecord.dev
& $probeAdb -s R5CW618VA1M shell pidof com.ksh321.songrecord.dev
& $probeAdb -s R5CW618VA1M shell am start -n com.ksh321.songrecord.dev/com.ksh321.songrecord.MainActivity
```

강제 종료 직후 `pidof`는 PID를 출력하지 않아야 하며, 재실행 화면의 최종 성공 문구는
`ANDROID STORAGE RESTART: PASS`다. 실제 기기 ID와 Activity 경로는 실행 전에 확인한다.
재설치나 앱 데이터 삭제 없이 기존 설치 앱을 재실행한다.

완료 후 평소 앱은 `flutter run --flavor dev -t lib/main.dart`로 다시 빌드·실행한다.
평소의 API 주소 설정이 있다면 해당 실행 인자를 함께 사용한다.

## TJ 번호 경쟁: 수정본 실제 MySQL 실행 통과

`verify_p04_tj_race.py` v2를 사용자 PC에서 다시 실행해 다음 결과를 확인했다.

| 검사 | 실제 결과 |
|---|---|
| 새 빈 DB에 V1~V7 설치 | 통과 |
| 같은 계정 중복 등록의 실제 잠금 대기 | 연결 31이 연결 30을 기다리는 상태 확인 |
| 첫 등록 커밋 | 둘째 등록은 MySQL 1062, 곡은 정확히 하나, 실패한 ID의 행 없음 |
| 첫 등록 롤백 | 연결 36이 연결 35를 기다린 뒤 둘째 등록만 커밋 |
| 다른 계정의 동일 번호 | 첫 계정 미커밋 중 둘째 계정 커밋, 두 계정에 각각 보존 |
| 선행 0을 포함한 TJ 번호 | 원래 문자열 보존 |
| 테스트 컨테이너·볼륨·네트워크 정리 | 통과 |

- 실행 프로젝트: `song-record-p0409-24838507c67c0014`
- MySQL/API 포트: 57234 / 57236
- 사용자 PC 증거 폴더: `%TEMP%/song-record-p0409-fudy7xsu`
- 증거 파일: `result.json`, `verification.log`
- 최종 출력: `P04-09 TJ number race verification passed.` 및 `TJ number race: PASS; cleanup: PASS`

Python 보조 코드의 `Android account-storage process recreation: NOT RUN by this script.`는
해당 스크립트가 Android 검사를 실행하지 않는다는 범위 표시다. 앞에서 확인한 별도 실기
`ANDROID STORAGE RESTART: PASS` 결과는 유지된다.

### 재실행 방법과 판정 조건

계획서 P04-09의 ‘번호 경쟁’을 명시적으로 확인하기 위해 `verify_p04_tj_race.py`를 추가했다.
이미 통과한 전체 회귀와 구분해 다음 명령으로 새 테스트 DB에 V1~V7을 한 번 설치하고 실행한다.

```powershell
py -3.14 infra/scripts/verify_p04_disposable.py --scope tj-race
```

1. 같은 계정·같은 TJ 번호를 두 연결이 동시에 등록한다. MySQL `data_lock_waits`에서 실제
   `uq_song_owner_reserved_tj` 잠금 충돌을 관측한 뒤 첫 연결을 커밋한다. 둘째 연결은 해당
   유일 인덱스의 오류 1062여야 하며 곡은 정확히 하나만 남아야 한다.
2. 같은 잠금 충돌에서 첫 연결을 롤백하면 대기 중이던 둘째 연결의 등록은 성공해야 한다.
3. 다른 계정이면 첫 연결이 미커밋인 동안에도 같은 번호로 둘째 연결이 커밋할 수 있어야 한다.
4. 최종 데이터에서 선행 0을 포함한 원래 번호와 계정 구분이 유지돼야 한다.

잠금 관측용 root 읽기는 새로 만든 검증 컨테이너 안에서만 수행한다. 접속 실패·SQL 구문 오류·
잠금 시간 초과·deadlock을 중복 거절 성공으로 취급하지 않는다.

### 최초 실패와 검사 코드 수정 기록

사용자 PC의 최초 실행은 빈 DB V1~V7 설치와 두 MySQL 연결 생성 후
`No actual TJ unique-index lock wait was observed`로 실패했다. 테스트 리소스 정리는 성공했다.
이 출력에는 실제 잠금 대기의 상세 행이 없어 서버 제약 실패로 단정하지 않는다.

- 실행 프로젝트: `song-record-p0409-f364b0ee8f475db9`
- MySQL/API 포트: 50602 / 50603
- 증거 폴더: `%TEMP%/song-record-p0409-xbgt_cy7`
- 결과: `TJ number race: FAIL; cleanup: PASS`

검사 코드에서 잠금을 생성한 Performance Schema 스레드와 잠금을 소유한 트랜잭션을
같게 취급한 문제를 확인했다. MySQL 8.4의 암시적 INSERT 잠금은 다른 연결의 요청 중 명시적
잠금 구조로 바뀔 수 있어, 생성 이벤트의 스레드 ID가 실제 소유자의 연결 ID와 다를 수 있다.
이는 [공식 잠금 코드](https://github.com/mysql/mysql-server/blob/8.4/storage/innobase/lock/lock0lock.cc)의
`lock_alloc`, `lock_rec_convert_impl_to_expl_for_trx`와
[Performance Schema 노출 코드](https://github.com/mysql/mysql-server/blob/8.4/storage/innobase/handler/p_s.cc)를
확인한 판단이다. 사용자 실패 당시의 정확한 잠금 행은 확보하지 못했으므로 이 조건이
해당 실행에서 발생했는지는 아직 직접 관측하지 않았다.

수정본 v2는 대기·차단 양쪽 `ENGINE_TRANSACTION_ID`를 `INNODB_TRX.TRX_ID`에 연결하고,
`TRX_MYSQL_THREAD_ID`로 실제 두 연결을 확인한다. 동일한 테스트 DB·song 테이블·TJ 유일
인덱스와 `WAITING`/`GRANTED` 상태를 모두 확인하는 성공 조건을 유지한다. 시간 초과나
예상 밖의 조기 응답에는 해당 테스트 연결·트랜잭션·잠금 진단을 남긴다.

SQLite에 관측 메타데이터만 구성한 회귀 검사 7개를 통과했다. 기존 스레드 조회가 0행을
반환하는 경우를 재현하고 수정 조회의 소유자 판별, 다른 소유자·인덱스·DB 거절, 대기 상태,
SQL 오류·관측 실패의 실패 처리를 확인했다. 이 모의 검사는 실제 MySQL 실행과 구분하며,
수정본의 사용자 PC 재실행 통과 결과는 위 표에 기록했다.

## 완료 범위와 후속 작업

1. 빈 MySQL 설치·증분 업그레이드·제약·번호 경쟁·기존 데이터 보존·서버/Android 재실행 검증 완료.
2. 합성 파일의 보존 검사를 실제 녹음·재생 통과로
   확대해 기록하지 않는다.
3. 로컬 스키마는 v1뿐이다. v1→v2 업그레이드는 존재하지 않으므로 검증했다고 기록하지 않는다.
   기존 테스트에는 미래 스키마 거절과 원본 보존, 연결 재열기와 트랜잭션 롤백이 포함돼 있다.
4. Android 프로세스 종료 검사는 OS 재부팅·기기 전원 차단·미완료 트랜잭션 중 종료와 구분한다.
5. 완료 기록과 보조 파일의 커밋·push 및 해당 커밋 CI 확인은 후속으로 진행한다.
6. 다음 기능 단계는 계획서 P05다. 이번 검증 작업에서 P05 기능 구현은 시작하지 않았다.

근거: [Flutter appFlavor](https://api.flutter.dev/flutter/services/appFlavor-constant.html),
[Android adb](https://developer.android.com/tools/adb),
[Docker Compose 환경·프로젝트 설정](https://docs.docker.com/compose/how-tos/environment-variables/envvars/),
[MySQL 잠금 대기 관측](https://dev.mysql.com/doc/refman/8.4/en/performance-schema-data-lock-waits-table.html).
