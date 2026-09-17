# P02-01~03 Android 녹음 시제품 검증

- 작성일: 2026-09-17
- 대상: P02-01 RecorderGateway, P02-02 권한·마이크 foreground service, P02-03 M4A 생성·재생
- 상태: 구현 및 CI 성공 / 실제 Android 기기 검증 대기

## 구현 범위

Flutter의 `RecorderGateway`가 MethodChannel과 EventChannel을 통해 Android 네이티브 녹음 서비스에 명령을 보내고 상태를 받는다. 화면이 다시 만들어지면 현재 서비스 상태를 한 번 조회하고 이후 상태 스트림을 다시 구독한다.

Android는 사용자가 화면에서 `녹음 시작`을 누른 경우에만 마이크 권한을 요청하고 microphone foreground service를 시작한다. 서비스는 진행 알림을 표시하고 앱 내부 영구 경로 `files/recordings`에 M4A 파일을 쓴다. 캐시 경로는 사용하지 않는다.

녹음 설정은 AAC, 96,000bps, 48,000Hz, 모노, MPEG-4 컨테이너다. 종료 후 `MediaExtractor`로 실제 오디오 트랙의 MIME·샘플링 주파수·채널·AAC 프로파일을 읽어 화면에 표시한다. `녹음 파일 재생 확인`은 같은 파일을 Android `MediaPlayer`로 재생한다.

이번 묶음에는 5분 30초·5분 50초 경고와 6분 자동 종료가 포함되지 않는다. 이는 P02-04 이후 작업이다.

## 자동 검사

- Flutter 정적 분석
- 기존 health 성공·실패 위젯 테스트
- 화면 재생성 시 녹음 상태 복원 위젯 테스트
- 네이티브 상태와 실제 오디오 정보 변환 단위 테스트
- dev debug Android APK 빌드로 Kotlin·Manifest·Flutter 연결 컴파일 확인


## CI 검증 결과

- GitHub Actions: [CI 실행 #6](https://github.com/ksh321/Song_Record/actions/runs/35198869345)
- Flutter analyze: 성공
- Flutter test: 8개 성공
- dev debug Android APK 빌드: 성공
- Spring Boot build/test: 성공
- MySQL Compose smoke test: 성공

## 실제 기기 확인 순서

1. Samsung SM A546S를 USB 디버깅 상태로 연결한다.
2. `apps/mobile`에서 아래 명령으로 dev 앱을 실행한다.

   ```powershell
   flutter run --flavor dev -t lib/main.dart
   ```

3. 화면을 아래로 내려 `녹음 시제품`에서 `녹음 시작`을 누른다.
4. 마이크 권한과 Android 13 이상 알림 권한을 허용한다.
5. 5~10초 동안 말한 뒤 `녹음 종료`를 누른다.
6. 다음 항목을 확인한다.
   - 상태가 `파일 생성 완료`
   - 파일 크기가 0보다 큼
   - 실제 코덱이 `audio/mp4a-latm`
   - 실제 샘플링이 `48000Hz`
   - 실제 채널이 `1`
   - AAC 프로파일이 표시되는 기기에서는 `2 (LC)`
7. `녹음 파일 재생 확인`을 눌러 방금 녹음한 소리가 재생되는지 확인한다.
8. 녹음 중 화면을 회전하거나 앱을 잠깐 다른 화면으로 전환했다 돌아와도 `녹음 중` 상태와 시간이 다시 표시되는지 확인한다.

## 완료 판정

CI가 모두 성공하고 실제 기기에서 권한 거절·재허용, 파일 생성, 실제 형식, 재생, 화면 재구독을 확인하면 P02-01~03을 완료로 바꾼다.
