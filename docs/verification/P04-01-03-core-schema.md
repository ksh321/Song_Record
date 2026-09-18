# P04 01부터 03까지 핵심 서버 스키마 검증

## 범위

이번 변경은 계정 소유권, 곡 번호 예약, 녹음 메타정보와 서버 파일 상태의 기반 테이블을 추가한다. API 업무 로직과 Flutter 로컬 DB는 각각 P06 이후와 P04-08에서 연결한다.

## 계정 스키마

- `app_user`: ACTIVE와 DELETING 수명 상태
- `auth_identity`: GOOGLE과 KAKAO 공급자 신원
- `auth_session`: 사용자와 소유 기기를 함께 검사하는 갱신 세션
- `device`: 계정 소유 기기
- `user_entitlement`: FREE 권한, 고정 10개, 1GB 한도와 revision

이메일에는 유일 제약을 두지 않는다. 로그인 신원은 `(provider, provider_user_id)`로만 유일하며, 세션은 `(user_id, device_id)` 복합 외래키를 사용한다.

## 곡 스키마

`song`은 UUID와 TJ 번호를 분리한다. `reserved_tj_number`는 TJ 곡이 ACTIVE, TRASHED, PURGE_PENDING일 때만 번호를 반환하는 저장 생성 열이다. `(user_id, reserved_tj_number)` 유일 인덱스가 생성 경쟁과 휴지통 중복을 DB에서 차단한다.

`song_source`는 검증된 TJ 원본 제목·가수·참조를 보존한다. 트리거는 MANUAL 곡이나 다른 계정 곡에 TJ 원본 행을 연결하지 못하게 한다.

## 녹음과 파일 스키마

- `recording`: 당시 곡명·가수·키·버전·시각·시간대 스냅샷
- `recording_file_spec`: SHA-256, 크기, 길이, AAC-LC·48kHz·모노 명세
- `recording_asset`: 서버 파일 상태와 검증 완료 객체 정보
- `recording_upload`: 예약부터 완료까지 개별 업로드 시도

개인 관계는 `(user_id, id)` 복합 외래키로 계정 소유권을 검사한다. 곡의 대표 녹음 외래키는 `(user_id, song_id, recording_id)`를 사용하여 같은 곡의 녹음만 가리킨다.

녹음은 DRAFT로 생성한다. SAVED 전환에는 곡명·가수·키와 파일 명세가 필요하다. SAVED 뒤에는 DRAFT로 되돌릴 수 없으며 PURGED 전까지 파일 명세를 수정하거나 삭제할 수 없다.

활성 업로드는 계정별 0번과 1번 슬롯만 사용한다. 유일 인덱스가 계정별 동시 2개와 같은 녹음의 활성 시도 1개를 강제한다.

## 실제 MySQL 검증 순서

1. MySQL 8.4를 빈 볼륨으로 시작한다.
2. Spring Boot와 Flyway를 목표 버전 1로 실행한다.
3. V1 테이블에 업그레이드 보존 확인 행을 넣는다.
4. 서버를 다시 실행해 V2까지 증분 마이그레이션한다.
5. V1 확인 행과 Flyway 이력 1, 2가 모두 남았는지 확인한다.
6. 허용 사례를 삽입하고 다음 잘못된 사례가 실제 DB에서 거절되는지 확인한다.

## 거절 사례

- 같은 공급자 사용자 ID를 다른 계정에 연결
- 다른 계정 기기로 세션 생성
- MANUAL 곡에 TJ 번호 또는 TJ 원본 연결
- 같은 계정의 보호 수명 곡에 같은 TJ 번호 사용
- 다른 계정 곡을 녹음에 연결
- 정의되지 않은 버전 저장
- 파일 명세 없이 SAVED 전환
- SAVED 파일 명세 수정·삭제와 SAVED에서 DRAFT 복귀
- 다른 곡 녹음을 대표 녹음으로 지정
- 최종 객체 정보 없는 STORED 상태
- 같은 녹음의 활성 업로드 중복
- 계정의 세 번째 활성 업로드와 종료 시도의 슬롯 점유

## 완료 기준

- Flyway V1에서 V2로 데이터 손실 없이 업그레이드된다.
- MySQL이 허용 사례를 저장하고 모든 거절 사례를 실패시킨다.
- Spring Boot 빌드와 Flutter 기존 회귀 테스트가 함께 성공한다.
