# ENV-GRADLE-LOOPBACK — 2026-09-30 원인 분리

기존 서버 실행 실패 3회와 새 Android APK 실패 1회를 보존한다. Gradle `help --offline --stacktrace`는 빌드 반복이 아닌 진단으로 수행했다. 사용자 데이터·방화벽·전역 Java 설정은 변경하지 않았다.

- JBR 21.0.10 및 Temurin 21.0.12.1에서 일반 Pipe/TCP loopback 진단은 통과했다.
- Gradle 스택은 `WEPollSelectorImpl → PipeImpl → UnixDomainSockets.connect`의 `Invalid argument: connect`를 가리켰다.
- `Selector.open()` 단독 검사로 같은 오류를 재현했다. 설치된 JDK src.zip의 UnixDomainSocketsUtil.java는 `jdk.net.unixdomain.tmpdir` 시스템 속성, net 속성, TEMP, java.io.tmpdir 순서로 경로를 고른다.
- 프로젝트 `.local/sock`를 `-Djdk.net.unixdomain.tmpdir=...`로 해당 Java 실행에 지정하자 Selector/Pipe/Socket 모두 PASS였다. 기본 임시 경로에서 실패하는 더 아래 OS 원인까지 확정하지는 않았다.
- 이 설정을 프로세스 범위 JAVA_TOOL_OPTIONS로 전달한 dev APK 빌드가 종료 0으로 성공했다. 기본 경로 문제 자체나 서버 실행/DB 준비까지 해결됐다고 확대하지 않는다. 원래 환경 변수는 finally로 복원한다.

진단 소스와 원문 로그는 `.local/workflow/LoopbackProbe.java`, `loopback-selector.log`, `loopback-shortdir.log`, `gradle-loopback-stack.log`에 보관한다. 비밀값이 있는 로그인 define 파일은 Git 제외 로컬 파일로만 유지한다. 앱 설치/계정/DB 데이터 변경은 수행하지 않았다.
빌드: flutter build apk --debug --flavor dev --dart-define-from-file=<Git 제외 로컬 파일> --dart-define=API_BASE_URL=http://127.0.0.1:8080. 제품 기준 2e6bd8826331caba39b3621e9ee63355fce10583, Gate 코드 적용 전에 생성. APK의 SHA256·생성시각을 로컬 provenance JSON에 저장하고 덮어쓰지 않는 사본으로 고정했다. 설치는 하지 않았다.
