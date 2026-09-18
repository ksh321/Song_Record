# P02-06 녹음 복구 저널 검증

## 구현 범위

- 녹음 시작 전에 UUID, 계정 범위, 임시 경로, 완료 경로, 시작 시각을 동기식 복구 저널에 기록한다.
- 상태를 `preparing → recording → finalizing → verified → completed` 순서로 갱신한다.
- 녹음 중에는 `recordings/.pending/{recordingId}.m4a`에 기록한다.
- 종료 후 실제 오디오 트랙, 길이, 크기, SHA-256을 확인한 뒤 `recordings/{recordingId}.m4a`로 이동한다.
- 앱 프로세스가 다시 시작되면 저널과 파일을 비교한다.
  - 재생 가능한 파일은 같은 recordingId로 완료 상태를 복구한다.
  - 마무리되지 않았거나 사라진 파일은 정상 완료로 처리하지 않고 복구 오류를 표시한다.
- 현재 P02 시제품에는 로그인 계정이 없으므로 `accountScope=prototype_device`를 기록한다. 실제 accountId 연결은 인증·로컬 DB 단계에서 교체한다.

## 자동 검증

- Flutter 상태 변환에서 `durationMs`, `sha256`, `recovered`, `recoveryState`를 확인한다.
- 복구 완료 상태가 화면에 복구 안내, 검증 길이, SHA-256, 재생 버튼을 표시하는지 위젯 테스트로 확인한다.
- Android 빌드로 저널 저장, 파일 검사, 복구 코드의 Kotlin 컴파일을 확인한다.

## 실기기 검증 절차

### 정상 완료 복원

1. 앱에서 5초 이상 녹음한다.
2. 녹음 종료 후 파일 재생이 되는지 확인한다.
3. 최근 앱 화면에서 앱을 제거하거나 Android Studio 실행을 종료한다.
4. 앱을 다시 실행한다.
5. 같은 녹음 ID와 파일 경로가 표시되는지 확인한다.
6. `이전 실행에서 완료된 녹음 파일을 복구했습니다.` 문구와 재생 버튼을 확인한다.
7. 재생 버튼으로 파일이 정상 재생되는지 확인한다.

### 중단 파일 보호

1. 녹음을 시작하고 5초 이상 기다린다.
2. PC에서 아래 명령으로 앱 프로세스를 종료한다.

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb shell am force-stop com.ksh321.songrecord.dev
```

3. 앱을 다시 실행한다.
4. 파일이 완전하면 같은 녹음 ID로 복구 완료되는지 확인한다.
5. 파일이 완전하지 않으면 `RECORDER_RECOVERY_INCOMPLETE` 오류가 표시되고 재생 버튼이 비활성화되는지 확인한다.

> 강제 종료 시점과 제조사 MediaRecorder 동작에 따라 파일이 복구될 수도 있고, 완전히 마무리되지 않을 수도 있다. 두 결과 모두 저널의 UUID를 유지하고 손상 가능 파일을 정상 완료로 표시하지 않는 것이 합격 기준이다.
