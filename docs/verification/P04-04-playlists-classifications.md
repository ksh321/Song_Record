# P04 01부터 04까지 재검토와 목록 분류 스키마 검증

검토일은 2026-09-21이며, 시작 커밋은 `be04ee8`이다. P04-01~03을 재검토해 V3 수정 마이그레이션을 추가하고, P04-04를 V4로 구현했다. 이미 적용된 V1·V2 파일과 체크섬은 변경하지 않았다.

## 기존 구현에서 수정한 문제

| 문제 | 영향 | V3 수정 |
|---|---|---|
| 선택 키의 NULL 조합 검사 | 모드만 있거나 반음만 있는 값이 MySQL CHECK의 UNKNOWN으로 통과 | 둘 다 NULL이거나 둘 다 유효한 값인 경우만 허용 |
| 활성 업로드 슬롯 NULL | 슬롯의 유일 인덱스를 피해 계정별 동시 2개 제한 우회 | 활성 상태에서 슬롯 NOT NULL과 0·1을 명시적으로 검사 |
| 파일 generation이 BIGINT | 설계 11.6의 객체 세대 UUID와 불일치 | BINARY(16) UUID로 전환하고 기존 숫자는 legacy_generation에 보존 |
| 파일 명세 변경과 SAVED 전환의 경쟁 | V2의 일반 SELECT가 이전 DRAFT 상태를 읽어 저장된 명세를 삭제·수정할 수 있음 | 부모 녹음과 파일 명세에 잠금 읽기 사용, 파일 명세의 소유자·기록 ID 변경 거절 |

첫 두 문제는 수정 전 V2에 잘못된 값을 실제 삽입해 재현했다. V3는 잘못된 기존 키·슬롯 데이터를 만나면 실패하며 값을 임의로 보정하지 않는다. 배포 전 백업과 해당 행의 검토가 필요하다. MySQL DDL은 전체 마이그레이션을 하나의 트랜잭션으로 롤백하지 않으므로 실패 시 Flyway 이력과 실제 적용된 제약을 함께 확인해야 한다.

generation 전환은 기존 object_key·크기·해시·상태·파일 바이트를 유지한다. 기존 generation이 있는 행에 새 UUID를 부여하고 숫자와 UUID의 대응을 같은 행에 남긴다. 후속 업로드·삭제 원장에서는 새 generation 열을 사용하며 legacy_generation은 참고용이다.

## P04-04 구현

- `playlist`: 계정별 소유권, 이름 1~100자, 양수 revision, 삭제 시각. 같은 이름을 허용한다.
- `playlist_item`: 계정이 일치하는 목록·곡만 연결하고, 같은 목록의 entry_key와 song_id 중복을 막는다. position은 0 이상 BIGINT이며 순서 일괄 갱신을 위해 position 자체는 유일 제약을 두지 않는다.
- 신규 곡 연결은 ACTIVE 곡만 허용한다. 기존 관계는 곡이 휴지통에 있어도 삭제 묶음 표시·복원에 사용할 수 있도록 유지한다. `hidden_by_batch_id`의 삭제 묶음 FK는 P04-06에서 연결한다.
- DB가 TJ 번호에서 `tj:번호`, 직접 등록곡 UUID에서 `manual:UUID`를 계산한다. 전달된 entry_key로 중복 검사를 우회할 수 없다. TJ 후보를 같은 번호의 곡에 연결할 때 항목 ID·위치·원본을 유지한다.
- KY 후보, 비정상 번호, 부분 후보 정보, 다른 번호의 곡 연결, 삭제된 목록에 대한 항목 추가·수정을 거절한다.
- `tag`: 이름과 별도의 정규화 비교키를 저장한다. 계정별 활성 비교키만 유일하며 archive 뒤에는 같은 이름을 새로 사용할 수 있다.
- `recording_tag`: 양쪽 계정 소유권과 녹음·태그 중복을 검사한다. DB가 연결 당시 이름을 저장하며 이름 변경·archive 뒤에도 유지한다. 기존 archived 관계는 유지할 수 있고 새 연결은 거절한다.
- D06에 따라 `condition_catalog`의 고정 네 단계와 녹음의 nullable 단일 condition_code를 구현했다. 초기값은 미선택이다. DB가 표시명 스냅샷을 만들고 일반 카탈로그 변경을 거절한다.

태그 비교키의 NFC·ASCII 소문자 정규화는 서버가 생성해야 한다. DB는 제공된 이진 비교키의 유일성을 강제하며 Unicode 정규화 자체를 대신하지 않는다. 전체 Unicode 일치 검증과 API에서 클라이언트 비교키를 받지 않는 처리는 P03 잔여 검증·P09에서 연결한다. 외부 후보의 진위, 전체 목록 revision·변경 로그, 중복 요청 멱등성, 목록 삭제 Job은 P07·P15·P19의 업무 계층 범위다.

## 실행 결과

Windows의 독립 MySQL 8.4.11을 127.0.0.1:33316에서 사용했다. 사용자 개발 DB에는 접속하거나 마이그레이션하지 않았다. Flyway 12.4.0과 Connector/J 9.7.0은 저장소 잠금 버전과 같다.

| 검증 | 결과 |
|---|---|
| V1 설치 → 보존 확인 행 → V2 적용 | 성공 |
| 기존 P04-01~03 검증 스크립트 | 22개 판정 통과 |
| V2 기존 STORED 객체 → V3·V4 업그레이드 | 성공. object_key, 숫자 7, UUID 16바이트, 1048576바이트 보존 |
| Flyway V1·V2·V3·V4 성공 이력 | 확인 |
| 같은 DB에서 Flyway migrate·validate 재실행 | 성공. 중복 적용 없음·체크섬 일치 |
| 별도 빈 DB에 Flyway V1~V4 일괄 설치 | 성공 |
| 확장 검증 스크립트 | 63개 판정 통과 |
| 동시성 검증 | 두 연결의 같은 목록 중복 추가, SAVED 우선/파일 명세 삭제 우선 양방향 경쟁 통과 |
| 잘못된 기존 값이 있는 V2 업그레이드 | 제약 오류로 거절. 합성 행을 명시적으로 보정한 뒤 재검증 성공 |
| 셸 구문·Git 공백 검사 | 통과 |
| Spring Boot test·bootJar | 환경 차단. Gradle compileJava 중 의존성 JAR의 toRealPath에서 AccessDeniedException |
| 이번 변경의 GitHub Actions | [602dab5의 실행 결과](https://github.com/ksh321/Song_Record/actions/runs/35579131995): 서버 전체 빌드·테스트와 MySQL 변경·제약·재시작 검사 성공 |
| Flutter | GitHub CI 분석·테스트·Android APK 빌드 통과. 앱 코드는 변경하지 않음 |
| 실기·화면 검증 | 이번 변경에서 미실행 |

로컬 Gradle 초기 연결 문제는 작업용 임시 디렉터리 지정으로 해소했으나, 이후 의존성 JAR 접근 오류는 재현됐다. 별도 Java 실행에서 실제 Flyway migrate·validate와 MySQL 검증은 정상 수행됐다. 이후 GitHub main 반영 후 원격 CI에서 전체 Spring Boot 빌드·테스트도 성공했으므로 로컬 환경 차단과 코드 검증 결과를 구분한다.

## 재실행 방법

CI는 `P04_DISPOSABLE_DB=1`인 임시 DB에서 `infra/scripts/verify_p04_migrations.sh`를 실행한다. V1 → V2 기존 검사 → V3·V4 확장 검사 → 서버 재기동 순서다. DB 테스트 전용 API 포트 기본값은 18084이며, 자기 프로세스의 시작 로그와 health를 함께 확인한다.

이미 V4까지 적용된 별도 임시 DB에서는 `infra` 폴더에서 `python3 scripts/verify_p04_extended_schema.py`를 실행한다. 기본 연결은 Docker Compose의 mysql이다. Windows 독립 MySQL은 MYSQL_TEST_CLIENT, MYSQL_PORT, MYSQL_USER, MYSQL_DATABASE 및 필요한 경우 MYSQL_PWD를 설정한다. 테스트는 합성 행을 넣으므로 매번 새 임시 DB를 사용한다.

기본 마이그레이션 사용자는 TRIGGER 외에 루틴 생성을 위한 CREATE ROUTINE·ALTER ROUTINE·EXECUTE 권한이 필요하며, 항목을 쓰는 업무 계정에는 `p04_playlist_item_identity` 실행 권한이 필요하다. CI의 DB 전용 계정은 DB 범위 권한을 사용한다. 운영 권한은 P24에서 분리한다.

P04-04 구현·GitHub 반영·로컬 및 CI DB 검증·원격 서버 빌드 검증을 마쳤다. 다음 기능 작업은 P04-05 보관과 용량 스키마다. 사용자 개발 DB의 실제 변경은 아직 수행하지 않았으며 V/X 전체 제품 검증을 통과한 것으로 집계하지 않는다.
