# P04 05 보관과 용량 스키마 검증

2026-09-21, 시작 커밋 `fd1450e`. 구현계획서 P04-05와 설계서 6~7·11.5에 따라 V5를 추가했다. 기존 V1~V4는 수정하지 않았다. 이번 범위는 서버 DB 구조이며 실제 업로드·삭제 API와 앱 화면은 포함하지 않는다.

## 구현한 구조

| 테이블 | 역할과 보장 |
|---|---|
| song_cloud_selection | 곡별 대표·최신·최저 역할. 같은 녹음 ID가 여러 역할을 맡을 수 있다. 계정과 곡까지 일치하는 복합 외래키로 다른 계정·다른 곡 참조를 막는다. |
| pin_slot | 계정별 1부터 시작하는 자리 번호. current와 pending을 함께 보관하므로 교체 중에도 기존 보호가 유지되고 슬롯은 하나다. |
| cloud_hold | PENDING_REPLACEMENT·WAITING_LOCAL_CONFIRM·ORPHAN_KEEP. 녹음·사유·관련 작업별 유일성을 적용하며 관련 작업이 NULL이어도 중복을 막는다. |
| cloud_cleanup | 대상 세대 UUID·체크섬·cloud revision·확인 방식·15분 이하 유효기간·상태·작업 임대·오류. 같은 generation의 활성 작업은 하나다. |
| storage_usage | 계정별 실제 used·아직 사용량에 포함되지 않은 reserved와 revision. 바이트는 음수가 아닌 BIGINT다. |
| global_storage_usage | id=1 단일 행. 전체 used·reserved·20,000,000,000바이트 기본 한도·임시 공간 관측량·업로드 잠금 상태. |

PinSlot 검사는 UserEntitlement 행을 잠그고 최신 커밋을 읽는다. 무료 기본 한도 10은 기존 UserEntitlement에서 가져오며, current와 pending의 교차 중복도 거절한다. 한도를 낮춰도 기존 슬롯을 지우지 않고 교체·취소·해제를 허용하되 한도 초과 상태의 신규 점유는 막는다. 신규 고정 대상은 ACTIVE·SAVED여야 하며 current는 STORED, pending은 DELETING이 아니어야 한다. 파일 없는 미연결 SAVED 녹음도 pending으로 자리를 예약할 수 있다.

CloudCleanup은 생성 시 현재 계정·녹음·세대·체크섬·revision이 일치하는 STORED 객체를 확인한다. 캡처한 객체 식별 정보는 이후 변경할 수 없다. 객체가 새 세대로 교체돼도 이전 정리 이력이 사라지지 않도록 현재 asset generation에 외래키를 걸지 않는다. 활성 상태는 WAITING_CONFIRMATION·CONFIRMED·DELETING·RETRY_WAIT, 종료 상태는 SUCCEEDED·CANCELLED·EXPIRED다. 재시도 중에도 활성 유일성을 유지하고 종료 시각을 요구한다.

## 기존 데이터 업그레이드

기존 계정마다 StorageUsage를 만들고 STORED·DELETING asset의 verified_size 합을 used로, RESERVED·UPLOADING·VERIFYING 업로드의 expected_size 합을 reserved로 초기화한다. 휴지통·미연결·정리 대기 파일도 실제 서버 사본이면 used에 포함한다. 종료된 업로드는 예약에서 제외하고 전체 합계를 GlobalStorageUsage에 넣는다. 역할이나 보호 사유의 개수로 파일 크기를 곱하지 않는다.

한도보다 사용량이 많다는 이유로 기존 데이터를 삭제하거나 마이그레이션을 거절하지 않는다. used+reserved+신규 크기의 개인·전체 한도 검사는 P12의 잠금 트랜잭션에서 구현한다. 이번 스키마의 숫자 CHECK를 업로드 승인 기능으로 간주하지 않는다.

실제 적용 전에는 백업과 현재 행을 확인하고 다른 서버·작업자의 쓰기를 멈춘 상태에서 적용해야 한다. 기존 카운터가 없는 상태에서 파일/업로드 상태가 동시에 바뀌면 초기 합계가 어긋날 수 있다. MySQL DDL은 전체 파일의 원자 롤백이 아니므로 실패 시 적용된 구조와 Flyway 이력을 함께 점검한다. 사용자 개발 DB에는 적용하지 않았다.

## 검증 기록

- Windows의 별도 MySQL 8.4.11, 127.0.0.1:33316을 사용한다. 사용자 개발 DB와 분리했다.
- 저장소 잠금 버전 Flyway 12.4.0·Connector/J 9.7.0으로 V4→V5 업그레이드와 빈 DB V1~V5 설치, 각 DB 재실행·체크섬 검증에 성공했다. 새 검사는 업그레이드 72개·빈 DB 70개 판정이 모두 통과했다.
- 기존 P04 확장 검사 63개를 재실행해 통과했다.
- 새 검사는 다른 계정·곡 참조, 역할 중복 허용, 고정 10번째 자리 경쟁, 오래된 REPEATABLE READ 스냅샷의 교차 중복 우회, 교체·취소·한도 축소, 보존 사유 중복, 정리 객체 식별·확인·재시도·이력, 음수·BIGINT·단일 전체 행을 다룬다.
- 업그레이드 전 합성 데이터는 휴지통 STORED 100바이트 + DELETING 500바이트, VERIFYING 77바이트, FAILED 99바이트, COMMITTED 100바이트다. V5 뒤 used=600, reserved=77을 기대한다.
- 첫 로컬 실행에서 시험용 MySQL의 Windows 시간대와 UTC 입력 차이가 드러났다. 공통 검사 접속을 UTC로 고정해 프로젝트의 Docker DB 설정과 맞췄다.
- GitHub main 코드 커밋은 [9d73f72](https://github.com/ksh321/Song_Record/commit/9d73f723bdf907e56e9255f0dc06b9c17096a59b)이다. [CI 실행](https://github.com/ksh321/Song_Record/actions/runs/35588779189)의 세 작업이 모두 성공했다. 서버 전체 빌드·테스트, MySQL 기존 22개·확장 63개·신규 72개 판정과 실제 서버 재시작, Flutter 분석·테스트·Android APK 빌드를 확인했다. 전체 최신 상태는 [진행 기록](../progress.md)을 따른다. 실제 기기·음성 파일 업로드·객체 삭제는 이번에 검증하지 않았다.

## 재실행과 후속 구현 경계

CI는 임시 DB에서 V1 → V2 기존 검사 22개 → V4 확장 검사 63개 → 업그레이드 합성 데이터 → V5 새 검사 → 서버 재시작 순서로 실행한다. V5 검사는 `P04_DISPOSABLE_DB=1`을 요구한다. 데이터가 들어 있는 일상 개발 DB에서는 실행하지 않는다.

`infra`에서 `python3 scripts/verify_p04_retention_schema.py --seed-upgrade`는 V4 전용 데이터 준비, 옵션 없는 실행은 바로 V5를 적용한 시험 DB의 검사다. 별도 Windows 클라이언트는 MYSQL_TEST_CLIENT·MYSQL_PORT·MYSQL_USER·MYSQL_DATABASE를 지정한다. 합성 ID를 사용하므로 검사마다 새 DB가 필요하다.

- P06/P07: 새 계정 생성 시 UserEntitlement·StorageUsage 생성과 정해진 잠금 순서 연결.
- P11: ACTIVE·SAVED 후보 계산, 대표·최신·최저 선정, 같은 고정 요청에 기존 슬롯 반환, revision·변경 로그·asset.cloud_revision 동시 갱신.
- P12: 개인·전체 한도와 예산 잠금 검사, 업로드 예약·확정·취소의 원자 반영, 재대조와 중복 집계 방지.
- P13: 실제 로컬 파일 검증·확인 토큰·현재 시각 만료 검사·정리 직전 무보호 재검사·상태 전이·lease와 R2 삭제. 성공 응답이나 DB의 SUCCEEDED 값만으로 실제 삭제를 증명하지 않는다. 실제 삭제 확인 후 사용량을 한 번만 차감한다.
- P04-06: Job·삭제 원장·동기화 구조. 현재 operation UUID는 아직 존재하지 않는 Job 테이블에 연결하지 않는다.

검증에 사용하는 마이그레이션 계정은 기존 TRIGGER와 CREATE ROUTINE·ALTER ROUTINE·EXECUTE 권한을 유지해야 한다. 운영 계정 분리는 P24 범위다.
