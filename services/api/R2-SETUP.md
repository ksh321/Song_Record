# P12-01 비공개 R2 연결

실제 R2 4개 역할의 연결·읽기 권한 분리는 통과했다. 개발 API/worker의 합성 객체 쓰기·읽기·삭제 및 권한 분리도 통과했다. 사용자가 버킷 4개 모두 공개 URL 비활성·사용자 지정 도메인 없음을 확인했다. 기본 설정에서는 연결을 활성화하지 않는다. 실제 R2 검증 전 P12-01 완료 또는 후속 P번호 착수로 처리하지 않는다.

## 환경과 역할
- 개발: `song-record-dev-temporary`, `song-record-dev-final`.
- 운영: `song-record-prod-temporary`, `song-record-prod-final`.
- 이름 앞부분은 바꿀 수 있으나 `-dev-temporary`, `-dev-final`, `-prod-temporary`, `-prod-final` 접미사는 환경 혼용 방지를 위해 검사한다.
- 모든 버킷은 비공개로 유지한다. r2.dev 공개 주소와 사용자 지정 공개 도메인을 활성화하지 않는다.
- 각 환경의 API 토큰은 해당 temporary 버킷만 Object Read & Write 권한을 갖는다. worker 토큰은 같은 환경 temporary/final 두 버킷만 접근한다. 개발·운영 및 API·worker 토큰을 재사용하지 않는다. 각 프로세스에는 해당 환경·역할의 자격 증명만 주입한다.
- SDK에 명시적 자격 증명을 주입한다. 기본 AWS 자격 증명 탐색이나 다른 환경/역할 값으로 대체하지 않는다. 앱에는 키를 넣지 않는다.

## 노트북의 일회용 키 입력
- 사용자 선택으로 평문 파일 및 DPAPI 저장 방식 모두 폐기. tools/r2_credentials.py는 자격 증명 파일을 쓰거나 읽는 기능이 없다.
- AI가 일회용 창을 실행하면 사용자가 dev.api/dev.worker/prod.api/prod.worker를 선택해 Access Key ID와 최신 Secret Access Key를 마스킹 입력란에 직접 넣고 **이번 입력으로 검사 — 저장 안 함**을 누른다.
- 검사 시작 시 입력란을 비운다. 키는 메모리 및 Java 검사 프로세스 stdin으로만 전달한다. 명령 인자·환경변수·로그·파일에 키를 넣지 않는다. 다음 검사에는 다시 입력해야 한다.
- AI는 reports/*.json의 허용된 결과값과 검사 시각만 읽는다. 기존 평문/암호화 파일·메모리·클립보드는 읽지 않는다.
- 프로그램이 의도적으로 키를 저장하지 않는다는 뜻이며, 런타임 메모리의 완전한 삭제·OS 페이징/덤프·클립보드 기록·동일 사용자/관리자의 접근 차단까지 보장하지 않는다.
- 과거에 저장된 파일은 이 프로그램이 읽거나 자동 정리하지 않는다. 과거 노출 우려가 있는 키는 롤 또는 취소 후 최신 키를 사용한다. 롤로 비밀값을 교체했다면 토큰 ID 유지 자체는 문제가 아니다.
- 이번 검사는 연결·읽기 권한 분리만 확인한다. 실제 쓰기/공개 접근/최종 저장 검증과 운영 서버 비밀 주입은 별도다.

## 검증과 다음 범위
- `R2Storage.verifyConnection()`은 API에서 임시 버킷, worker에서 임시/최종 버킷의 HEAD를 검사한다. 읽기 확인이 공개 접근 차단·최종 쓰기 거절의 증명은 아니다.
- 실제 설정 후 AI가 별도 합성 객체로 개발 연결과 권한 범위를 확인하고, 공개 접근 차단 및 개발/운영·API/worker 토큰 분리를 대조해야 한다. 사용자 파일을 테스트에 사용하지 않는다. 운영 배포와 유료 서비스 활성화는 자동 실행하지 않는다.
- 객체 키는 서버 UUID로만 생성: `temporary/{owner}/{recording}/{attempt}` 및 `recordings/{owner}/{recording}/{generation}.m4a`. 임시/최종 버킷도 분리한다.
- P12-03 승인 이후 P12-04에서 임시 PUT URL 발급, P12-09에서 검증 바이트 최종 기록을 연결한다. 현재는 연결 경계·키 생성만 제공한다.
- AWS SDK v2 2.55.12와 URLConnection 전송만 사용하며 종속성은 gradle.lockfile로 고정한다. endpoint HTTPS, region auto, path style, chunked encoding 비활성화, 요청 시간 제한 적용.

근거: [Cloudflare Java SDK 예제](https://developers.cloudflare.com/r2/examples/aws/aws-sdk-java/), [R2 토큰과 버킷별 권한](https://developers.cloudflare.com/r2/api/tokens/). 공식 문서 확인 2026-10-08.

## 개발 쓰기 확인 (USER-044)
- `--development-write` 실행은 dev.api/dev.worker 두 역할만 표시한다. 기존 읽기 보고서는 유지하고 `development-reports`에 별도 고정 결과를 기록한다.
- 개발 버킷의 고유 `connection-check/{UUID}.txt`에 합성 바이트만 조건부 PUT → GET 바이트 비교 → 서명 없는 S3 GET의 403 또는 400+InvalidArgument/Authorization 확인 → 해당 시험 객체 DELETE. API final PUT은 403이어야 통과한다.
- 운영 버킷 쓰기는 거절한다. 기존 객체와 충돌(412)하면 삭제하지 않는다. PUT 응답 유실 시 생성됐을 수 있는 해당 시험 키만 정리 시도하며, 정리 실패는 CLEANUP_FAILED로 통과를 막는다.
- S3 비서명 거절만으로 r2.dev/사용자 지정 도메인 비공개를 증명하지 않는다. 사용자가 4개 버킷 Settings에서 Public Development URL 비활성 및 Custom Domains 연결 없음을 별도 확인한다. [공식 공개 버킷 문서](https://developers.cloudflare.com/r2/buckets/public-buckets/) 기준, 두 공개 경로는 서로 독립적이다.
