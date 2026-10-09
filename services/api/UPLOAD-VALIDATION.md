# 실제 오디오 검증과 자원 제한

P12-07 / P12-08, 요구사항 R070·R071. P12-06의 다운로드 결과를 실제 바이트로 검증한다. 최종 객체·DB 확정은 P12-09의 별도 단계다.

- 같은 검증의 다운로드·검사·전체 디코딩이 하나의 60초 단조 시계 예산을 공유한다. 중첩된 검증은 시간을 새로 시작하지 않는다. 블록된 읽기는 남은 시간에 취소·abort하고 소비자를 실행하지 않는다.
- 한 초기 worker 프로세스에서 모든 UploadVerification/AudioValidator 인스턴스가 전체 2개 슬롯을 공유한다. 여러 worker 프로세스로 늘리는 배포는 지원하지 않으며 별도 분산 슬롯 정책 없이 수평 확장하지 않는다.
- 실제 읽기 상한 6MiB, 초과 1바이트에서 즉시 중단. 과대 UPLOAD_TOO_LARGE, 슬롯 포화 UPLOAD_WORKER_BUSY, 시간·메모리·출력 제한 FILE_VALIDATION_TIMEOUT. 정상 파일·작업 완료/자산 STORED로 확정하지 않는다.
- native 검증에는 파일별 512MiB 한도: Windows Job Object의 process/job committed memory, Linux RLIMIT_AS 주소 공간 한도. Windows는 helper와 하위 도구의 합계도 제한한다. Linux는 각 상속 프로세스 주소 공간을 제한하며 초기 helper 하나·디코더 하나만 실행한다. FFmpeg 단일 할당은 추가 16MiB 제한.
- ffprobe stdout은 64KiB까지만 보관. 디코딩 PCM은 최대 (361×48000+1024)×2바이트까지만 계수하며 보관하지 않는다. stderr는 제한된 조각으로 메모리 오류만 분류하고 출력·기록하지 않는다.
- 제한 초과 시 하위 프로세스와 helper를 종료한다. 자기 입력·helper 파일만 제거, 다음 작업 슬롯을 복구한다. 작업 종료 cleanup에는 짧은 프로세스 종료 확인 시간이 추가될 수 있다.
- JVM에서 다운로드/검증 바이트는 위 입력 상한과 동시 2개로 제한한다. native 메모리 제한은 JVM 전체 힙 제한을 대신하지 않는다.

## 실행 환경
worker 서버에 Python 3·FFmpeg·ffprobe가 필요하다. 기본 실행 이름은 Windows python / Linux python3, ffmpeg, ffprobe이다. 필요하면 songrecord.upload.python/ffmpeg/ffprobe로 설치된 실행 파일 경로를 지정한다. 쉘 문자열로 실행하지 않는다. helper는 jar 리소스에서 자기 작업 디렉터리로 추출한다. OS 제한 적용 실패는 FILE_SANDBOX_UNAVAILABLE로 거절하고 무제한 실행으로 우회하지 않는다. 도구 누락은 FILE_VALIDATOR_UNAVAILABLE.

다운로드가 성공하거나 PUT을 완료했다는 사실만으로 파일 보관 완료가 아니다. 제한 내 실제 검증 이후 기존 lease·계정·녹음 상태를 다시 확인하며, 확정은 후속 단계에서 검증한 같은 바이트만 사용한다.

설계 근거: 원본 계획 P12-08 XML p00663~665, 설계 8.2 p00497. 구현 참조: [Windows Job Object](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects), [Python resource 한도](https://docs.python.org/3/library/resource.html), [FFmpeg 옵션](https://ffmpeg.org/ffmpeg.html).

## P12-09 최종 객체 확정
검증된 바이트는 사전 예약 final key에 If-None-Match 생성하며 기존 키는 실제 바이트가 같은 경우만 재사용한다. 네트워크 작업은 DB 잠금 밖이고 사용량·자산·시도 확정은 lease로 보호된 트랜잭션이다. 초기 단일 worker 역할에서 `songrecord.storage.enabled=true`, `songrecord.storage.role=worker`, `songrecord.upload.scheduling-enabled=true`로 UPLOAD_VERIFY 실행을 켠다. API 역할에는 최종 writer/스케줄이 없다.

## P12-10 재실행·만료
worker는 사전 final key가 존재하면 그 바이트를 재검증하고 동일 attempt를 복구한다. 영속 job retry와60초 예산을 공유한다. 실패·만료·취소는 예약만1회 해제하고 기존 자산을 유지한다. 미확정 객체 정리는 live lease 없음·자산 미연결·2분 grace 후 별도 스케줄에서 수행한다. cancel API는 앱 인증·기기·멱등 키·소유권을 요구한다.
