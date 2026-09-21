# MySQL 개발 환경

P01-04에서는 Docker Compose로 로컬 MySQL을 실행한다. 앱은 DB에 직접 연결하지 않고 Spring Boot API만 DB에 연결한다.

## 고정값

| 항목 | 값 |
|---|---|
| MySQL | `8.4.11` (8.4 LTS) |
| 이미지 | `mysql:8.4.11@sha256:85b9bf2e29cf836ecb8c2a15a935d4ba0c606631dff1dd79531a11983c638f2a` |
| 문자셋·정렬 | `utf8mb4` · `utf8mb4_0900_ai_ci` |
| 시간대 | UTC |
| 외부 접속 | `127.0.0.1:3306`만 허용 |
| 데이터 | Docker named volume `song_record_mysql_data` |

계획 당시 기준인 8.4.12 공식 이미지를 조회했지만 사용할 수 없어, 같은 8.4 LTS 계열에서 실제 조회된 8.4.11 이미지를 digest로 고정했다. 8.4.12가 공식 배포되면 별도 검증 후 갱신한다.

## 1. 비밀값 준비

처음 환경을 만들 때만 아래 복사를 실행한다. 이미 `.env`가 있으면 복사하지 말고 기존 설정을 유지한다. 이미 초기화된 DB는 `.env`의 비밀번호만 바꿔도 자동으로 변경되지 않는다.

PowerShell에서 저장소의 `infra` 폴더로 이동한 뒤 실행한다.

```powershell
Copy-Item .env.example .env
notepad .env
```

`MYSQL_PASSWORD`와 `MYSQL_ROOT_PASSWORD`에 서로 다른 로컬 개발용 비밀번호를 넣는다. 빈 값으로 두지 않는다. `.env`는 Git 제외 대상이며 비밀번호를 커밋·이슈·채팅에 붙여넣지 않는다.

## 2. MySQL 실행

```powershell
docker compose config --quiet
docker compose up -d
docker compose ps
```

`docker compose ps`에서 `song-record-mysql`이 `healthy`이면 준비 완료다. 처음 실행은 이미지 다운로드와 초기화 때문에 시간이 걸릴 수 있다.

로그가 필요하면 다음만 확인한다.

```powershell
docker compose logs --tail=50 mysql
```

## 3. Spring Boot 연결

새 PowerShell을 열고 저장소의 `services/api`로 이동한 뒤 실행한다.

```powershell
$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = "3306"
$env:DB_NAME = "song_record"
$env:DB_USER = "song_record"
$env:DB_PASSWORD = Read-Host "MYSQL_PASSWORD와 같은 값을 입력"
.\gradlew.bat bootRun --args="--spring.profiles.active=dev"
```

`Started ApiApplication`이 나오면 개발 프로필에서 DB 연결과 서버 기동이 성공한 것이다. 실행 중인 서버는 `Ctrl+C`로 종료한다.

Spring Boot는 `infra/.env`를 자동으로 읽지 않는다. Compose는 `.env`를 MySQL 컨테이너에 전달하고, 서버에는 위와 같이 `DB_*` 환경변수를 별도로 넣는다.

## 4. 재시작 후 데이터 유지 확인

PowerShell의 중첩 따옴표 문제를 피하기 위해 MySQL 대화형 콘솔에서 확인한다.

```powershell
docker compose exec mysql mysql -u song_record -p song_record
```

`.env`의 `MYSQL_PASSWORD`를 입력한 뒤 다음 SQL을 실행한다.

```sql
CREATE TABLE p01_04_persistence_check (id INT PRIMARY KEY);
INSERT INTO p01_04_persistence_check (id) VALUES (1);
SELECT * FROM p01_04_persistence_check;
exit;
```

컨테이너를 재시작하고 `healthy`를 확인한다.

```powershell
docker compose restart mysql
Start-Sleep -Seconds 30
docker compose ps
docker compose exec mysql mysql -u song_record -p song_record
```

다시 접속한 콘솔에서 다음을 실행한다.

```sql
SELECT * FROM p01_04_persistence_check;
DROP TABLE p01_04_persistence_check;
exit;
```

재시작 뒤에도 조회 결과에 `id = 1`이 보이면 named volume의 영속성 검증이 끝난다. 마지막 명령은 확인용 임시 테이블을 제거한다.

## 종료와 주의사항

데이터를 보존한 채 멈출 때는 `docker compose stop`, 다시 켤 때는 `docker compose up -d`를 사용한다. `docker compose down -v`는 named volume과 DB 데이터를 삭제하므로 초기화가 정말 필요할 때만 사용한다.

P01-04에서는 연결과 영속성까지만 확인한다. Flyway 초기 마이그레이션과 Hibernate 스키마 검증은 P01-05에서 구성한다.


## P01-04 실제 검증 결과

2026-09-17 Windows 11·Docker Desktop 환경에서 MySQL 컨테이너 `healthy`, Spring Boot `dev` 프로필의 Hikari 연결, MySQL 재시작 후 확인 데이터 유지와 임시 테이블 제거를 확인했다.

최초 연결에서는 수동으로 입력한 `DB_PASSWORD` 불일치로 MySQL 1045 오류가 발생했다. 컨테이너에 적용된 `MYSQL_PASSWORD`와 동일한 값을 Spring의 `DB_PASSWORD`로 설정해 해결했다. Hibernate Dialect 오류는 인증 실패로 DB 메타데이터를 읽지 못해 따라온 2차 오류였다.


## P01-08 CI

최초 P01-08은 연결 확인 검사였으며, 현재 `MySQL migrations and constraints` 작업으로 확장됐다. 실제 개발 비밀번호 대신 CI 안에서만 사용하는 임시값으로 `.env`를 만들고, Compose 설정과 MySQL 접속을 확인한다.

현재 검사는 실제 Spring Boot 서버를 켜서 Flyway V1 → V2 → V3·V4 증분 변경, 기존 데이터 보존, 기존 22개·확장 63개 DB 판정, 재기동 시 이력 검증을 수행한다. 완료 후 CI 전용 컨테이너와 저장공간만 제거한다. 사용자 PC의 개발 DB에는 적용하지 않는다.

`P04_DISPOSABLE_DB=1`은 시험용 DB임을 명시하는 안전 확인값이다. 검증 스크립트를 실제 기록이 들어 있는 DB에서 실행하지 않는다. 기존 개발 DB를 변경하기 전에는 백업과 기존 값의 적합성부터 확인한다. 쉬운 설명은 [DB 작업 안내](../docs/database-guide.md), 실행 증거와 제한은 [P04 검증 보고서](../docs/verification/P04-04-playlists-classifications.md)를 참고한다.
