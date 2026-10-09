# P14-08 파일 없음 복원 안내 (원수)

- 승인 범위 P14-01~08, 사용자 지정 gpt-6.1-sol/medium 고정 현재 대화 직접 작업. 앞 P14-07 ed96f289617330ced4097715909afa26613dfa77 필수 CI37920030618 PASS 유지, finish07/begin08 직접 측정 연결.
- 원본 계획서 실제 Word p739~741·설계서 2.5 p204~218·8.4 p503~505·R077/D04 대조. UI_REFERENCE/팔레트 및 기존 녹음 표시 구조 유지.
- RecordingFileStatus에 canPlay/filesConfirmedAbsent/안내 문구 추가, RecordingPlaybackActions를 검증된 fileStatus가 있는 RecordingRow에 연결. 검증된 현재 기기 파일 또는 실제 STORED 근거만 재생 허용하며 고정/자동 보관 선택·QUEUED/UPLOADING/VERIFYING·정보 동기화 완료만으로 허용하지 않음. 삭제된 정보는 우선 복원 상태 확인.
- 실제 로컬 파일은 서버 UNKNOWN이어도 로컬 재생 가능. 두 파일 없음이 확인된 상태와 상태를 확인할 수 없는 UNKNOWN을 구분하여 후자를 영구 손실로 단정하지 않음. 서버 정리 중/보관 중을 백업 완료로 표시하지 않음.
- 재생 불가인 녹음의 metadata는 유지, 원래 기기·사용자가 보관한 M4A·백업 확인 경로를 안내. 파일 복원 뒤 실제 검증이 필요하다고 명시. 이후 P21 백업 가져오기 구현을 현재 수행하거나 이미 구현했다고 주장하지 않음. row 상세 접근과 재생 버튼 콜백은 별도이며 현재 계정 player/인증 URL 권한 그대로 유지.
- 명령 한 번의 일괄 로컬: flutter analyze --no-pub No issues, flutter test --no-pub 전체846 PASS(82초), flutter build apk --debug --flavor dev --no-pub PASS(22.8초). 새 회귀3: 누락/보관 선택/대기/정리 중/UNKNOWN 재생 제한, 실제 local/STORED 가능, 정보 유지/복원 안내·백업 미완료 고지. 상세 로그 Git 제외 p14-08.
- 현재 모델 별도 검토: 완료 조건·diff·실행 결과·기존 file status/row 회귀·현재 기기 근거와 보관 역할 구분·정보 보존·삭제 상태 대조. 새 native/서버/파일 조작이 없는 안내 표시 변경으로 별도 사용자 실기 요청 없음. source 지문 review-source.json. 다른 에이전트/모델 호출 없음.
- 최종 SHA 필수 CI는 푸시 후 확인. P14-01~07의 최종 CI 요약만 해당 기존 검증 기록과 함께 커밋하며 사용자 기존 변경/이력은 보존. 직접 할 일0건. P15 착수 권한 없음.
- 개념: 녹음 정보를 가진 것과 재생 가능한 실제 오디오 사본을 가진 것은 별개의 상태다.
