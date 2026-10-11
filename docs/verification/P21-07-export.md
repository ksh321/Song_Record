# P21-07 ZIP 생성과 저장

## 요구사항·구현
- 원본 계획서 v1.0 P21-07(p954–956), 설계서 10.1·10.2, R102–R106, D10. 화면은 원본 HTML backup-export/backup-partial, UI_REFERENCE, 기존 팔레트·AppTheme를 따른다.
- export_zip.dart: 고정 schema 1 manifest.json·data.json·읽기용 recordings.csv·audio/{recording_id}.m4a를 UTF-8 Stored ZIP으로 만든다. 인증·기기 절대 경로·파일시스템 속성·링크를 ZIP에 넣지 않는다. 파일별 검증된 해시·크기·유한 6MiB를 대조한다. 중앙 디렉터리·CRC·종료 레코드·실제 디스크 전체 해시와 길이를 확인한 뒤 export.zip.part를 최종 내부 ZIP으로 바꾼다. ZIP64 범위를 넘으면 실패하며 조용히 잘라 쓰지 않는다.
- ZIP과 메타정보의 해시를 함께 묶어 재개 시 이전 ZIP에 새 data/manifest를 붙이지 못하게 한다. 취소·손상·출력 실패는 기존 ZIP·원본을 보존한다. 사용자 안내: 개인정보·메모·녹음이 포함된 비암호화 ZIP이며 앱 밖 사본은 삭제·탈퇴로 회수되지 않는다.
- export_job.dart: 계정 전용 exports/{export_id}/에 정제된 data/manifest·파일별 완료/해시·시각/커서·ZIP 해시·외부 저장 여부를 저장한다. .part 쓰기·flush·rename 후 마지막 checkpoint를 갱신한다. 앱 재시작 시 계정·작업 ID·data/manifest 해시·포함 파일별 해시·ZIP 해시를 다시 확인한다. 손상된 작업은 거절하고 기존 ZIP/원본은 지우지 않는다. 비밀값·URL·원시 로컬 journal을 저장하지 않는다.
- AccountPaths는 제한된 백업 파일명과 .part만 허용하며 기존 계정 경로·링크 검사를 유지한다. AccountStore.privateExportFile은 현재 계정을 전후 확인한다.
- 기존 AudioExportBridge를 재사용해 exportBackup 메서드와 application/zip 시스템 ACTION_CREATE_DOCUMENT를 연결한다. 정확한 현재 계정 exports/{id}/export.zip만 허용한다. 녹음 중·동시 출력·다른 계정·링크·기존 내용이 있는 외부 위치를 거절한다. 64KiB 단위 복사와 전후 전체 해시·크기·현재 계정 확인으로 큰 ZIP 전체를 메모리에 올리지 않는다. 복사 루프 제한 5분. 외부 content URI를 다시 읽어 해시가 같아야 저장 완료를 반환한다. 실패한 사용자 URI는 임의 삭제하지 않고 미완성 사본 가능성을 알린다.
- tool/backup_export_verification.dart: 개인 계정과 분리한 시험 계정·합성 M4A·실제 SQLite/파일·동일 네이티브 파일 선택기로 취소·저장·재시작을 검사한다. 계정 DB를 초기화하지 않는다. 공식 설정 화면 연결과 진행/결과/재시도는 P21-08 범위다.

## 실제 검사·별도 검토
- 영향 3개 PASS: ZIP 중앙 디렉터리와 실제 내용·체크섬, 손상/취소 시 이전 ZIP/원본 보존, 재개·계정 거절·체크포인트 손상 거절·ZIP와 다른 메타정보 묶음 거절.
- Python 표준 zipfile 독립 검증: 4개 항목·모든 CRC PASS, manifest 파일 수 1 확인. 합성 시험 ZIP이며 개인 녹음이 아니다.
- 최종 flutter analyze --no-pub: No issues found.
- 최종 flutter test --no-pub --reporter compact: 전체 1,047 PASS. 로그 .local/workflow/p21-07/all-tests-final.log.
- Android searchVerification debug APK 빌드 PASS(47.4초).
- 첫 영향 시험은 합성 baseline에 확인 상태 행이 없어 실패하여 시험 자료를 보완했다. 최초 분석의 시험 앱 함수 인자/중괄호·unused import를 보완했다. 전체 검사 실행 중 검토 보완이 반영돼 컴파일 파일 버전이 섞인 실행은 중단·무효 처리했고, 소스 고정 후 위 최종 전체 검사를 다시 실행했다. 동일 근본 원인의 3회 수정·재검증 실패가 아니며 모델 상향 없음.
- 현재 gpt-6.1-sol/medium 별도 검토: 요구 범위, 원본 불변, 임시 파일/정상 ZIP 분리, ZIP 헤더/중앙 디렉터리/실제 CRC, 현재 계정·경로 제한, 파일 선택기 취소/출력 실패, 메타정보와 ZIP 결합, 해시 검증 후 재개, 개인정보 안내를 대조했다. 별도 에이전트/모델 호출 없음.

## 실제 설치·현재 대기
- 초기에 R5CW618VA1M device였으나 최종 설치 시 no devices/emulators found. 설치·시스템 저장·재시작 검사는 미완료다. APK 빌드를 실기로 대체하지 않는다.
- USER-089 USB 연결·잠금 해제 요청을 내가할일.md와 user-action-records.md에 기록하고 ntfy 서버 접수를 확인했다. 폰 실제 수신은 미확인이다.
- 필수 실기 전 커밋·푸시는 하지 않는다. P21-08/09에 아직 착수하지 않았다. 승인 끝은 P21-09.

## 커밋·CI
- 기준 SHA: 6177a6c4052aaaa14f926bfcca707b9031ee2a26. 실기 완료 후 정확한 파일만 커밋·푸시하고 Flutter 필수 CI를 확인한다.

## 실제 설치 검증 완료
- USER-089 회신 후 R5CW618VA1M device 및 APK install -r Success. 별도 합성 계정에서 비암호화 개인정보 안내와 시스템 다운로드 저장 화면 확인. 저장 취소 후 내부 ZIP/합성 원본 보존 표시, 실제 저장 후 네이티브 전체 체크섬 검증 완료 표시 확인.
- 실제 외부 출력 ZIP 30,772바이트를 내려받아 Python zipfile의 4개 항목·모든 CRC·manifest 포함 파일1개 확인 PASS. 합성 음이며 개인 녹음/R2 시험이라고 주장하지 않는다.
- 검증 앱 강제 종료·재시작 후 기존 작업 해시 확인·재개 완료 표시. 정상 ZIP/기존 계정 DB 초기화 없음. XML/시험 ZIP 로그는 .local/workflow/p21-07 제외. USER-089 완료로 직접 할 일에서 제거. 필수 실기 대기 해소, 커밋/필수 CI 진행.
