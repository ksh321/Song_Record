# 기존 AWS 실험 서버 집계 관측

백업·복구 설치 시 `backup.py`·`restore.py`·`execution_lock.py`를 같은 operations 디렉터리에 함께 둔다. 삭제 원장 점검과 같은 `backup/execution.lock`을 사용하며, 백업·복구는 최대60초 기다린 뒤 실패 처리한다. 잠금 없이 실행하거나 기존 성공 보고서를 갱신해 숨기지 않는다. 원장 점검은 기존 BUSY 처리로 다음 실행에 재개한다.

P25-06의 이미 승인된 실험 서버에만 설치한다. 서버 생성·자격 증명 이전·공개 배포 도구가 아니다. 기존 API/DB/worker나 노트북 validation 환경을 교체하지 않는다.

관리자가 `/opt/song-record-experiment/operations`를 root0700으로 준비하고, 검사한 실행 JAR을 `api-operator.jar`, 해당 SHA256을 `artifact.json`의 `sha256`으로 보관한다. `observe.py`는 root0600, 두 systemd unit은 `/etc/systemd/system`에 둔다. 실제 호스트·자격 증명·설치 영수증은 Git 제외 로컬 기록에서 관리한다.

관측기는 기존 실험 프로젝트·DB/user·전용 DB 네트워크와 JAR 지문을 확인한다. 기존 원격 실행 상태의 DB 암호 하나만 별도 root0600 파일로 읽는다. 일회용 컨테이너는 DB 네트워크만 사용하며 공개 포트·R2 키·개인 녹음 파일을 받지 않는다. 메모리256MiB·CPU0.25, 읽기 전용 파일시스템·전체 capability 제거·최대 실행시간 제한을 적용한다. 기존 앱 프로세스나 DB 볼륨은 재시작하거나 초기화하지 않는다.

`python3 /opt/song-record-experiment/operations/observe.py`의 실제 성공 후 `song-record-observation.timer`를 활성화한다. 5분마다 AI 호출 없이 집계를 읽는다. 사용자 중단 marker가 있으면 서비스는 실행하지 않는다. `latest.json`은 마지막 성공, `failure.json`은 실패 시각을 보존하므로 최신 실패가 성공보다 새로우면 정상으로 취급하지 않는다.

현재 출력은 서버 관측 집계뿐이다. 클라이언트 실제 재생·오프라인 사용을 추정하지 않고, 알림 연결과 출시 준비 완료도 주장하지 않는다. 비용 조회·백업·삭제 원장·작업자 활성화는 각 권한과 검증이 필요한 별도 연결이다. 노트북의 기존 비용/백업 도구를 DB 이름만 바꿔 실행하거나 다른 DB를 자동 선택하지 않는다.

## 승인된 비용·경고 연결

P25-06 USER-126 승인으로 기존 Cloudflare 분석 조회 토큰과 ntfy 비공개 topic만 같은 서버의 `/etc/song-record-experiment/monitoring.json`에 root0600으로 보관했다. R2 객체 쓰기 권한·백업 키·복구 암호를 이전한 승인이 아니다. 기존 세 역할이나 이 두 값으로 백업 권한을 대신하지 않는다.

`cost.py`는 시간당 공식 가격 일치·Cloudflare 분석 권한 분리·사용량 범위·ECB 환율 신선도를 확인한다. 기존 추정식과 5/6/7만원 알림/경고/비용 잠금을 재사용한다. 허용된 `CostOperator`가 비용 소유 필드만 갱신하고 수동·객체 대조 잠금은 유지한다. 실패 시 마지막 정상 값과 실패 시각을 보존하고 0원을 주입하지 않는다. R2 추정에는 AWS 크레딧 차감·VM/디스크/IP/전송 비용이 포함되지 않는다. Free plan을 Paid로 전환하거나 자동 결제 경로를 만들지 않는다.

공유 operator bridge는 집계/비용과 `BackupLedgerOperator`의 snapshot/ack, `RestoreValidationOperator`의 migrate/metadata/check만 허용한다. 임의 클래스·retire·authorize-fixture는 거부한다. 복구 operator에는 원본 DB 암호를 주입하지 않고 새 임시 DB의 제한된 계정만 stdin으로 전달한다. 비용 관측·백업 원장 ACK는 각 소유 필드만 갱신한다. 새 JAR은 기존 API 프로세스 교체 없이 별도 제한 컨테이너에서 사용한다. 파일 보관 준비가 끝날 때까지 별도의 신규 업로드 수동 잠금은 유지한다.

`health.py`는 5분마다 연결된 집계의 15분 신선도·비용의 26시간 신선도·최근 실패와 성공의 순서·HTTPS 인증서 24시간 잔여를 점검한다. 경고 기록은 보호된 `operational-checks/latest.json`에 둔다. 백업·삭제 원장·복구·작업자 대조의 미연결은 별도 출시 조건으로 표시하고 정상으로 대체하지 않는다. `notify.py`는 기존 고정 문구만 전송하고 동일 사건의 전송 의도를 먼저 기록한다. 결과 불명확한 전송을 자동 반복하지 않으며 서버 접수와 실제 폰 수신을 구분한다.

## 승인된 독립 백업과 복구

USER128/129 승인·직접 등록으로 `song-record-experiment-backup` 비공개 Standard 버킷 한 개와 그 버킷만 접근하는 별도 키를 연결했다. 새 master/instance와 암호화 복구 봉투를 사용하며 기존 노트북 백업/키/카탈로그는 그대로 보존한다. 복구 암호 평문은 Windows나 AWS에 저장하지 않는다. Windows 등록본은 CurrentUser DPAPI, AWS 전용 설정은 기존 승인된 서버의 root0700/0600이다. 서버 관리자 침해까지 방어한다고 주장하지 않는다.

`backup.py`는 실험 DB만 일관된 스냅샷으로 만들고, 그 DB가 참조하는 확정 파일만 암호화해 게시한다. 삭제 원장 검증·독립 미러 게시/읽기 확인/현재 revision ACK가 선행하며 미분류 객체가 있으면 실패한다. 일일 복구 지점 최대7개, 매시간 확인한다. `restore.py`는 새로운 임시 DB/제한 계정에만 복원하고 현재 원장을 재적용한다. 파일 해시와 네트워크 없는 ffmpeg 디코드를 검사한 뒤 이번 실행이 만든 임시 DB/계정만 정리한다. 원본 DB 대체·원본 녹음 삭제는 하지 않는다. 매월 자동 검사와 5분 상태 감시는 AI 호출 없이 동작한다.

최초 실제 결과: DB 백업1점·원장0개 PASS, 별도 DB의 사용자2/녹음0 복구·임시 복사본 정리 PASS. 약55초는 데이터 복구 시간이며 서비스 전체 복구나 물리 기기 재생 증거가 아니다. 실제 녹음이 없어 파일 백업/디코드0개, `physical_restore_playback=NOT_EXERCISED`·`release_ready=false`를 유지한다. 연결된 백업/원장/복구의 실패·기한 초과는 기존 승인된 폰 경고 경로로 알린다. R2 전체 비용에는 새 백업 버킷도 합산하며 AWS 크레딧은 별도다.

## 업로드 활성화 전 저장 공간 분리

AWS 앱 세 역할은 기존 노트북 staging 버킷 쌍에서 전용 experiment 버킷 쌍으로 전환했다. `UploadInventory.daily`는 자기 DB에 없는 세대 파일을 고아로 판단하므로 서로 다른 DB의 객체를 공유하지 않는다. 수동 업로드 잠금은 유지한다. 자동 정리·삭제는 USER132가 승인한 실험 DB·전용 두 버킷 범위로만 활성화·검증하며 현재 개인 계정의 시험 탈퇴를 만들지 않는다.

`song-record-experiment-temporary` / `song-record-experiment-final` 두 비공개 Standard 버킷과 별도 api/worker/playback 키를 생성·등록·전달해 실제 전환을 확인했다. 명시적인 `songrecord.deployment.storage-scope=experiment`와 실험 DB/user가 동시에 맞을 때만 고정 쌍을 허용한다. 기존 staging/prod 기본 계약과 DB·API·계정·세션은 보존했다. 이전 AWS 공유 키 사본은 관리자 전용으로 보존하며 활성 앱·백업에서 사용하지 않는다. 상세 실행 결과는 P25-06 검증 기록을 따른다.
