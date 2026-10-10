# P18-09 — 파일 필터의 정확한 개수

- 원수 요청 gpt-6.1-sol/medium. 원본 계획 p858–860·D02/D03/D04·R032·X09 대조. 현재 모델 직접 구현·별도 검토.
- 전체 ACTIVE·SAVED metadata와 현재 계정 local_recording_files 명세·실제 디스크 검증·서버 파일 증거·동기화 완료 상태를 하나의 SQLite 읽기 트랜잭션에서 동결. 네트워크 한 페이지 후처리를 하지 않으며 음성 전체 다운로드 없음.
- 계정별 파일 인덱스는 최초 실제 검증 결과를 메모리에 캐시하고 명세/크기/mtime/ctime/경로 상태 변화 때 다시 해시 검증. 권한/I/O/경로 불명확은 UNKNOWN이며 정상 사본으로 세지 않음. 재생·삭제의 기존 실제 재검증 경로 유지. DB/원본 파일 쓰기·삭제 없음.
- 동결된 전체 집합에 필터→정렬→COUNT→50개 페이지. 로컬 전용 cursor는 계정·환경·lease·조건/정렬/키 규격·원본 fingerprint·조회 세대·마지막 고유 정렬 키에 결합. 다음 페이지는 마지막 키 뒤부터 선택. 데이터·파일 상태·조건·계정 변경은 첫 페이지와 count로 초기화, 낡은 cursor 거절. limit1–100 검증.
- 초기 baseline 미완료·파일 UNKNOWN은 ‘현재 확인된 N개’/확인 불가를 표시하고 확정0건으로 오표시하지 않음. 로컬 정보 기준과 마지막 동기화 시각 표시. 필터 취소는 기존 조건 유지.
- 현재 모델 별도 검토: 원본/D04·전체 데이터 범위·같은 읽기 snapshot·파일 캐시 무효화·계정 fencing·cursor 조건·잠정 개수·기존 API/파일 lookup 영향 대조. 비동기 필터·정렬 회신도 scope가 변경됐으면 적용하지 않음.
- 변경 파일: account_store.dart, recording_file_status.dart, recording_catalog.dart, local_repository.dart, recording_workspace.dart, recording_list.dart, recording_order.dart, recording_pages.dart, recording_verification.dart, recording_catalog_test.dart.
- 영향20 PASS(6초), 분석0(6.2초). 110개 목록의 첫50개 밖 일치60개를 찾는 필터·연결 페이지, 실제 계정DB111개와 파일 손상/복원/삭제 후 metadata 보존·계정전환, provisional0·페이지 리셋 검사. 단순 스타일7개 보완. 전체·빌드·실기·커밋·CI는 진행 중.

## 최종 보완·로컬 검사
- 폰 검사에서 새 DB 초기 생성 시각을 마지막 동기화 시각으로 읽는 누락 발견. 완료 baseline+APPLIED+resume 없음 근거가 있을 때만 시각을 표시하도록 수정하고 초기 미동기화 lastSync null 회귀 추가. 실제 서버 조회 시각을 추정하지 않음.
- 최종 분석0(10.1초), 영향10 PASS(4초), 전체958 PASS(1분46초), APK17.7초. 앞20개 영향 검사와 함께 원본 조건 대조. 최종 설치본 확인은 다음 단계.

- 최종 설치-r Success. 실제 NotificationShade·deviceLocked=1로 최종 UI 확인 대기 USER-082. 미커밋 코드 보존, CI 미실행. USB 재연결·기존 녹음 반복 불필요. 해제 후 남은 실기·커밋·푸시·CI 및 P18-10 계속.

## 최종 설치본 확인
- USER-082 회신 이후 SM_A546S MainActivity 전면·deviceLocked=0 실제 확인. 마지막 동기화 확인된 기록 없음, 현재 확인된1개, 초기 baseline 미완료 안내 정상. 파일 없음 필터 적용 시 현재 확인된0개·파일 상태 확인 불가 안내, 확정 빈 결과 오표시 없음. 초기화 적용 후 필터0·1개 복원, 상세 티어S·메모·미연결·키/버전 보존. 다수 페이지는 로컬110/111개 검사 근거이며 실제 폰1개 검사로 확대하지 않음.
- 증거: .local/workflow/p18-09/ui-unlocked.xml, ui-filtered.xml, ui-reset-applied.xml, ui-detail.xml (Git 제외). 현재 모델 별도 검토 지적 해결 후 최종 소스·958개 검사·실기 대조 PASS. 커밋·필수 CI는 다음 단계.
