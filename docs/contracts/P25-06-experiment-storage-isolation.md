# P25-06 AWS 실험 저장 공간 분리 변경안

상태: USER130 `AWS 전용 앱 저장 공간 분리 허용` 승인 후 비공개 버킷2개 생성·USER131 세 역할 최초 키 입력 대기. 기존 업로드 수동 잠금과 업로드/계정 삭제 스케줄러 비활성 유지. 실제 키 전달·서버 분리 전환은 아직 미실행이다.

## 문제와 근거

노트북 검증 DB와 AWS `song_record_experiment`는 서로 다른 DB인데 현재 `song-record-staging-dev-temporary` / `song-record-staging-dev-final`을 공유한다. `UploadInventory.daily()`는 현재 DB에 연결되지 않은 확정 세대를 유예시간 뒤 `R2Storage.deleteUncommittedFinal()`로 정리한다. 따라서 AWS 작업자를 그대로 활성화하면 노트북 검증 DB가 참조하는 객체를 AWS의 고아 객체로 판단할 수 있다. 기존 파일을 지우거나 이동하는 방식으로 해결하지 않는다.

## 적용할 정확한 변경

- 새 비공개 Standard 버킷 `song-record-experiment-temporary`, `song-record-experiment-final` 두 개. 공개 URL·사용자 도메인 없음, 기존 개발/운영/노트북 검증/백업 버킷 보존.
- 새 `experiment.api`: temporary 하나 Object Read & Write. 새 `experiment.worker`: 새 temporary/final 두 개 Object Read & Write. 새 `experiment.playback`: 새 final 하나 Object Read only. 관리자 권한·모든 버킷 접근 금지.
- 최초 키 입력은 별도 마스킹 창에서 사용자 직접 처리, 이후 CurrentUser DPAPI 자동 사용. 세 새 역할만 승인된 기존 AWS의 root0700/0600 전용 설정에 고정 SSH로 전달. 기존 백업 키/복구 암호 변경 없음.
- 서버는 명시적인 `songrecord.deployment.storage-scope=experiment`, staging profile, `DB_NAME`/`DB_USER` 모두 `song_record_experiment`일 때만 새 고정 버킷 쌍을 허용한다. 기본 staging/prod 이름 검증은 유지하고 혼합/오타/다른 DB를 거부한다.
- AWS 전용 새 버킷에 노트북 자료를 복사하지 않는다. 실제 AWS DB에 확정 파일 참조가 없음을 다시 확인한 뒤 두 앱 역할의 설정과 백업 원본 조회만 새 쌍으로 바꾼다. 기존 AWS 공유 키 파일 삭제는 자동 승인 검토에서 명시적 삭제 승인 부족으로 거절됐다. 안전한 대안으로 해당 관리자 전용 파일을 그대로 보존하고 새 앱·백업의 활성 설정에서는 사용하지 않는다. 노트북 등록/Cloudflare 기존 토큰을 폐기하지 않는다. 이후 서버 사본 삭제는 별도 명시적 승인 전 실행하지 않는다.
- API/worker의 설정 반영 재기동에는 기존 영속 DB/계정·로그인·기기 데이터를 보존한다. DB 초기화·앱 데이터 삭제·공개 범위 확대·AWS Paid/Upgrade 전환 없음. 새 연결의 역할별 허용/403·기존 버킷 접근 거부·백업/삭제 원장·일일 대조를 검증한 후에만 업로드 잠금 해제를 판단한다.

## 비용과 검증 경계

새 버킷도 같은 Cloudflare 계정의 기존 무료 사용량에 합산한다. 정액 가입이나 AWS 유료 전환을 만들지 않으며, R2 무료량 초과 비용 가능성은 기존 비용 감시와 잠금을 적용한다. 버킷 분리는 비용 상한 보장이 아니라 DB별 객체 소유권/정리 범위 격리다. 실제 녹음 업로드·복구·재생과 P25-06 필수 CI는 아직 통과하지 않았다.
