# P06-01 개발 인증 설정 확정 (2026-09-24)

> 현재 상태 (2026-09-29): **기존 기능 사용자 검증 완료**. 기준 HEAD와 확인 원문은 [사용자 확인 기록](../progress.md#user-acceptance-20260929)을 따른다. 아래 검증 대기/미실행 표현과 체크리스트는 당시 이력이며, 문서 부족만으로 재실기를 요청하지 않는다. 개별 사례의 실행 횟수·명령·기기를 새로 확인한 것으로 기록하지 않는다. 이후 변경과 영향 범위는 별도로 검증한다.

사용자가 직접 전달하고 Google 클라이언트 유형까지 확인한 값이다.

| 항목 | dev 값 |
|---|---|
| Android applicationId | `com.ksh321.songrecord.dev` |
| Google Cloud 프로젝트 | `song-record-dev` |
| Google Android client ID | `660802266773-dbbf9dnhdf4rog335tnhnm38keks376n.apps.googleusercontent.com` |
| Google Web/server client ID | `660802266773-jcpijgltjgupkt0s78qraah6ki9iju0c.apps.googleusercontent.com` |
| SHA-1 | `EE:9D:7E:5E:E7:3D:6E:44:88:6E:33:54:0B:83:08:82:45:1D:82:C5` |
| SHA-256 | `E0:FB:DB:61:E5:DC:B9:1C:77:EC:06:D4:A0:F0:E5:B8:53:A4:27:29:7A:AC:06:39:75:73:58:03:51:3B:CB:67` |
| Kakao 앱 ID | `1586938` |
| Kakao Native App Key | `710c5008600b80c7d0cb8010e8f031d6` |
| Kakao 키 해시 (SHA-1 바이트의 Base64) | `7p1+Xuc9bkSIbjNUC4MIgkUdgsU=` |
| Kakao scheme | `kakao710c5008600b80c7d0cb8010e8f031d6` |
| Kakao native callback | `kakao710c5008600b80c7d0cb8010e8f031d6://oauth` |

Google 서버 증명은 ID token(JWT), aud는 위 Web/server client ID다.
Android client ID를 서버 aud 허용 목록에 추가하지 않는다.
카카오 증명은 SDK access token이다. P06-03에서 공식 access_token_info 조회로 검증한다.
Google SDK/카카오 SDK 앱 로그인 실연결은 P06-06이며 현재 로그인 성공을 검증한 상태는 아니다.
카카오 활성화와 Android 등록 내용은 실로그인 시 최종 검증한다.

공개 설정: 이 문서와 추후 flavor별 앱 설정. 앱 ID, OAuth client ID, native key, 인증서 지문은 비밀키가 아니다.
서버 비밀값: 배포 환경의 secret store 또는 gitignore된 로컬 환경 파일. Admin Key, client secret,
서비스 계정 private key, 앱 세션 서명키, refresh token 원문을 Git/Flutter 자산에 넣지 않는다.
P06-02의 ID token 공개키 검증에는 Google client secret을 사용하지 않는다.

staging applicationId: `com.ksh321.songrecord.staging`, prod: `com.ksh321.songrecord`.
staging/prod 공급자 앱·클라이언트 ID·배포 인증서·리디렉션은 아직 미등록/미확정이다.
dev 인증서를 복사해 운영 완료로 표시하지 않는다. Play App Signing 적용 시 실제 앱 서명 인증서로 등록한다.

## 서버 적용

추가 profile `google-auth`가 켜진 경우에만 검증 Bean을 활성화한다.
`GOOGLE_SERVER_CLIENT_ID` 환경변수는 배포 환경별 Web/server client ID를 명시한다.
현재 단계는 내부 검증 어댑터이며 HTTP 로그인/계정 생성/세션 발급을 열지 않는다.

```powershell
$env:GOOGLE_SERVER_CLIENT_ID = "660802266773-jcpijgltjgupkt0s78qraah6ki9iju0c.apps.googleusercontent.com"
```

실서비스 연결 시 `dev,google-auth` 또는 해당 환경 profile과 함께 사용한다.
기존 bootstrap/health 검증은 설정 없이도 계속 실행된다.

P06-03: `kakao-auth` profile과 `KAKAO_APP_ID=1586938`을 사용한다.
`bootstrap,kakao-auth`는 검증기만, `dev,kakao-auth`는 DB 계정 조회도 활성화한다.
카카오 Native App Key를 서버 앱 ID 환경변수에 넣지 않는다. 이 검증에는 Admin Key가 필요 없다.
