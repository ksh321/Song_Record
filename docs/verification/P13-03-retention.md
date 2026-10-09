# P13-03 로컬 보존 실제 확인 (원수)

- 계획 p00689~691, 설계 p00433~437, R060/V18. P13-02 최종 f45e930 필수 CI PASS 후 finish→begin. 요청·관측 Sol6.1/medium 고정. 실기 회신은 실제 rollout/turn ID resume로 이어서 측정.
- AccountStore의 실제 영속 파일 읽기를 재사용해 같은 owner/recording/checksum/size를 확인한다. 파일이 없거나 과거 DB 보고만 남으면 LocalPreservation→HttpPreservationDownload가 현재 객체를 다운로드한 뒤 검증·영속 저장·재검사한다. 반환 성공은 서버 삭제 승인이 아니며 15분 토큰/fence는 P13-04 후속 범위.
- 저장은 현재 계정의 검사된 private 경로와 합성 작업 전용 임시 파일만 사용한다. 바이트·크기 검증→flush→rename→디스크 재검사 후 DB 기록. 다른 내용의 기존 로컬 원본, 다른 계정, 활성 cleanup_fence를 덮어쓰지 않는다. 계정 전환 뒤 늦은 다운로드는 저장/보존 확인하지 않는다. 잘못된 내용이나 안전하지 않은 경로는 서버 사본을 계속 유지해야 하는 실패로 반환한다.
- PreservationDownloads/Controller/R2GetSigner: 인증 계정의 현재 STORED 자산과 서버형 final 객체 키만 5분 GET URL로 제공, no-store. 앱은 ticket 전체 식별자·revision·expiry 대조, HTTPS R2 호스트만 GET, 리다이렉트 차단·최대 크기/시간 제한·API 인증 헤더 미전달. 값/키/URL 원문 로그 없음. 서버 storage.enabled 설정과 기존 DPAPI 자격 사용 경계 유지.
- 새 계약 경로 /recordings/{id}/preservation-url를 OpenAPI와 실제 컨트롤러 대조 검사에 추가. 설계 변경 없이 기존 로컬 보존 다운로드 구현. 새 migration 없음.
- 한 명령 .local/workflow/p13-03/check-local.ps1. 서버 test/bootJar PASS52초: XML601/실행526/조건부75/실패0/오류0. 계약 PASS(7 wire examples,141 boundaries). Flutter analyze PASS2.7초, 전체 테스트812 PASS67초, 별도 verification APK PASS72.6초. 로그 server/contract/analyze/mobile/apk.log. 서버 통과 뒤 계약 환경을 기존 contract-venv-modern으로 이어 실행(continue-local.ps1), 불필요한 서버 반복 없음.
- 최초 서버 검사 원인 P13-03-CONTRACT-REGISTER: 새 실제 컨트롤러가 기존 명시적 경로 대조 목록에 미등록, 수정1회 후 전체 PASS. 계약 Python 라이브러리 미설치 오류는 기존 venv 재사용으로 해결한 환경 오류. 신규 Dart 괄호 스타일14건 수정 후 analyze PASS, 기준/테스트 완화 없음.
- local_preservation_fixture/test: 실제 임시 영속 파일과 SQLite로 파일 없음 다운로드, 정상 재확인/다운로드 생략, 과거 기록만 남은 파일 복원, 다른 내용 원본 덮어쓰기 금지, 전송 중 계정 전환, 다른 계정 총6조건 대조. HTTP 로컬 통신 검사에서 ticket 불일치·리다이렉트 차단·스토리지 인증 미전달 확인. 서버 검사에서 STORED 키/세대만 서명하고 다른 ID·DELETING 미서명. 모의 통신을 실제 R2 통신이라 부르지 않는다.
- 별도 현재 모델 검토: 원본 완료 기준·실제 diff/검사·owner/UUID/hash/size·영속 파일/symlink·기존 원본 보존·계정 세션 guard·temp 범위·다운로드 상한/timeout/redirect·객체 식별자·서명 권한·민감값 로그·DB 상태와 파일 경계 대조. 변경 부분 형식 지적 해결, 검토 완료.
- USER-050 실제 Android 파일 검사 필요. 현재 검증 APK는 com.ksh321.songrecord.preservation 별도 앱, 개인 DEV 데이터 보존. 사용자 USB 회신 처음에는 adb0/WindowsSAMSUNGDEVICE, 재연결 회신 후 adb device1 확인, 설치 진행. 사용자6개 통과 결과 대기. 실기 전 커밋/푸시하지 않음. P13-04~10 미착수.
- 학습: 과거에 파일이 있었다는 DB 기록이나 다른 기기 보고는 현재 기기의 마지막 사본 증거가 아니다. 실제 바이트·영속 경로를 확인해야 서버 정리의 다음 단계로 진행할 수 있다.

- 설치 환경 오류: 기존 verification 패키지와 신규 debug 인증서 불일치(INSTALL_FAILED_UPDATE_INCOMPATIBLE). 기존 앱 삭제/데이터 초기화를 하지 않고 preservation 별도 flavor/package를 추가했다. 새 빌드/설치/실기 확인 대기.

- preservation 별도 설치본 assemblePreservationDebug PASS66.9초. adb install -r Success, com.ksh321.songrecord.preservation MainActivity 실행 성공. 기존 verification 서명/앱/데이터 유지. USER-050 실제 폰6개 결과 대기.

- USER-050 사용자 “6개 모두 통과” 회신으로 실제 Android 설치본6조건 통과. 직접 할 일에서 제거, 실기 조건 충족. 별도 모델 재호출·재실기 없음. 이제 커밋·푸시·현재 SHA 필수 CI 진행.
