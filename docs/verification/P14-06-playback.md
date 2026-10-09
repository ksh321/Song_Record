# P14-06 M4A 내보내기 (원수)

- 순차 승인 P14-01~08, 사용자 지정 gpt-6.1-sol/medium 현재 대화 직접 구현·별도 검토. P14-05 최종6c2b135a5e9a11dc79747c2895638bb8b216da86 CI37914023098 PASS 완료 유지, 사용량 finish05/begin06 직접 연결.
- 원본 계획서 실제 Word p733~735·설계서 p505·R076 대조. Android 공식 SAF 문서 https://developer.android.com/training/data-storage/shared/documents-files 에 따른 ACTION_CREATE_DOCUMENT/audio-mp4 사용. 제품 공개 공유 URL 생성 없음.
- RecordingExport: 현재 계정 LocalAudioLookup의 실제 크기/해시가 맞는 SAVED 또는 완료 INPUT_PENDING만 내보내기. 곡명/가수의 경로·제어문자 제거, 예약명·빈 이름·유니코드 길이 처리. RecordingExportButton에서 앱 밖 사본은 삭제·탈퇴로 회수할 수 없음을 사전 안내.
- AudioExportBridge/MainActivity: 시스템 선택기 취소 처리, 계정/녹음 UUID·환경·정확한 사설 파일 경로/실제 hash 확인, 최대6MiB snapshot을 사본으로 저장. 내보내기 중 native 계정 변경·백업 중첩 차단. 파일 핸들 AutoCloseOutputStream으로 정리. 결과 URI를 임의 로컬 경로로 받지 않음.
- SAF의 기본 중복 번호 처리 사용, 비어 있지 않거나 크기를 확인할 수 없는 목적지는 덮어쓰기를 거절. 저장 후 목적지 크기/hash 재확인. 실패 시 사용자 URI를 임의 삭제하지 않고 미완성 사본 가능성을 안내. 원본/메타정보/입력 일지 수정·삭제 없음.
- 일괄 로컬: analyze No issues, 전체839 테스트 PASS, preservation APK build PASS. 초기 시험 코드 readJournal 반환형/스타일 오류 수정(동작 실패와 구분). 별도 검토에서 유니코드 파일명 제한/FD 소유권 보완; 해당 export2 테스트 재통과·최종 APK build18.6초 PASS. diff 공백 검사 PASS. 상세 Git 제외 p14-06 로그.
- 현재 모델 검토: 완료 기준·diff·검사·취소/권한/계정/덮어쓰기/원본 보존 대조. 독립 에이전트 검토/별도 모델 호출 없음. source hash review-source.json.
- 설치: R5CW618VA1M device, update install Success, 실화면 P14-06 준비 완료. 초기 화면 추출 null은 잠든 화면을 깨워 재확인 해결, 테스트 실패나 통과로 혼동하지 않음.
- USER-056 시스템 저장 2회·이름 구분·외부 재생·취소 실기 대기. 미커밋 변경 위6파일·현재 기록. CI 아직 실행 전, P14-07~08 미착수. 실행 중 R2 fixture/CI/빌드 없음. 직접 할 일1건.
- 개념: 내보내기는 계정 내부 원본을 유지하면서 사용자가 고른 외부 위치에 독립 사본을 만드는 동작이다.

## 실기 회신
- USER-056 ‘모두 통과’: 저장·중복 이름·외부 재생·취소 통과로 필수 실기 종료. 현재 커밋·CI 확인 단계이며 P14-07~08 아직 미착수.
