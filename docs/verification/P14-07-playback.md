# P14-07 이 기기 파일 정리 (원수)

- P14-01~08 순차 승인·6.1-sol/medium 고정 현재 대화 직접 작업. 앞 P14-06 최종112fda3b778cb2568121a15fe6032cde662158c4 필수 CI PASS·완료 폰 알림 서버 접수, finish06/begin07 연결.
- 원본 계획 실제 Word p736~738·설계 9.1 p506~515 대조. 관련 R060/R065/R077·D04 및 기존 P13 cleanup confirmation/fence 계약을 유지. 데이터 삭제 정책·서버 삭제 권한 확대 없음.
- DeviceFileCleanup/Preview, DeviceFileCleanupButton, AccountStore.removeConfirmedDeviceAudio 추가. 최근 동기화된 서버 상태를 표시하되 실시간 백업 보장으로 오표시하지 않음. 동일 SHA/크기 STORED 사본 확인이 없으면 명시적 손실 체크를 추가 요구. 확인창 이후 서버 evidence·현재 파일·계정 변경 시 새 확인 필요.
- 기기 파일 정리는 녹음 기록 삭제와 별도 메뉴/확인 문구. 사용자가 확인한 계정/녹음 UUID의 실제 경로/해시/크기만 제거하며 metadata_copies·local_mutations·recording_journals·서버 파일·외부 내보내기 사본 유지. local_recording_files만 MISSING 표시. 삭제와 DB 표시 사이 중단이 생겨도 실제 파일 조회가 우선이며 실패를 ‘정리하지 않음’으로 단정하지 않음.
- 같은 계정 직렬 실행/SQLite transaction 안에서 cleanup_fence와 PREPARING/CONFIRMED 결과를 대조하여 보호된 원본을 삭제하지 않음. 기기 시각/미확정 응답으로 fence를 풀지 않음. 기존 매칭 terminal 처리 이후만 보호 해제. 새 schema/DB 초기화/개인 데이터 삭제 없음.
- 일괄 로컬: analyze No issues·전체842 테스트 PASS(82초)·APK build33.2초 PASS. 시험용 recoveryData 반환형·새 import/style 오류는 기능 수정 실패와 구분해 해결. 별도 현재 모델 검토에서 STORED라도 다른 바이트면 손실 확인 필요·server 근거 변경 시 재확인 지적 해결.
- 보완 영향 검사: device cleanup4·기존 cleanup confirmation2·file status6, 총12 PASS(3초), analyze No issues·최종 APK build17.4초 PASS·diff 공백 검사 PASS. 기존 P13 expiry/reopen 보호 테스트 유지. 원시 로그/검토 지문 Git 제외 .local/workflow/p14-07.
- 실기 자동 검사: R5CW618VA1M update install Success. P14-07 전용 합성 파일·합성 metadata 생성, 미확정 fence 실제 삭제 거절/파일 유지 확인 후 합성 CANCELLED로 해제. 실제 UI ‘정리 보호 검사 통과 · 합성 파일만 준비 완료’. 제품 서버 terminal 실기로 확대하지 않음.
- USER-057 확인창/취소/손실 체크/실제 파일만 제거·정보 유지 사용자 검증 대기. 미커밋 위5파일/현재 기록. live CI/빌드/R2 fixture 없음. P14-08 미착수. 직접 할 일1건.
- 검토는 현재 모델이 완료 기준·diff·계정·원본/metadata 보존·회귀 결과와 대조한 별도 단계이며 추가 AI/Worker 호출 없음.
- 개념: 파일 정리와 기록 삭제는 서로 다른 동작이며, 마지막 사본으로 쓰는 로컬 파일의 보호 장치는 서버 결과 확정 전까지 유지해야 한다.

## 실기 회신
- USER-057 ‘모두 통과’: 취소·손실 안내/명시적 정리·파일만 제거/녹음 정보 유지 통과. 커밋·필수 CI 확인 단계, P14-08 미착수.

## 최종 완료
- 최종 SHA ed96f289617330ced4097715909afa26613dfa77, 필수 CI 37920030618 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
