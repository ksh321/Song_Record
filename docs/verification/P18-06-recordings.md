# P18-06 — 재연결과 미연결 화면

- 원수: 요청 gpt-6.1-sol/medium. 현재 모델이 직접 구현·별도 검토·통합. 원본 계획서 v1.0 p849–851, 기존 녹음 song 전용 API·계정 lease·metadata 계약 대조.

## 구현과 현재 모델 별도 검토
- 검색 가능한 내 곡 선택 → 명시 확인 → 연결 저장, 곡 연결 해제 → 미연결. 저장 전 취소는 변경 없음. 당시 제목·가수·키·버전·메모·티어 등 전체 스냅샷을 유지하며 song_id/link_revision만 변경.
- 기존 저장 명령·전송 큐 재사용. 입력 스냅샷 동결, 변경 필드 정확한 제한, 계정 소유·ACTIVE 대상·stale editor·lease·트랜잭션·operation 재시도 검토. Song 쓰기나 당시 속성 연쇄 변경 없음. 재시도는 같은 준비 명령 사용.
- 변경 파일: account_store.dart, local_repository.dart, recording_relink_screen.dart, recording_detail_screen.dart, recording_verification.dart, recording_relink_test.dart.
- 소유 필드가 포함된 수신 스냅샷의 일반 patch 제한과 전용 명령을 구분해 수정. strict Song 생성 응답 시험 fixture의 envelope와 필수 null 필드를 보완. 서로 다른 원인별로 확인했으며 검사 삭제·완화 없음.

## 로컬 검사
- 영향16 PASS: 초기 입력/편집/연결 검사. 전체944 PASS(1분40초), analyze0(4.1초), APK 빌드 PASS21.0초.
- 전용 song endpoint의 정확한 두 필드·순차 ACK, 연결/해제 후 재시작·원본 보존, 삭제 대상·stale/계정 변경 차단, 검색·취소·조회 오류 보존 확인. 실제 서버 전송으로 확대하지 않음.
- 비공개 로그 .local/workflow/p18-06/.

## 실제 설치본 PASS
- SM_A546S USB 연결·잠금 해제 확인 후 install-r Success. P18-06 검증 앱에서 다른 곡 선택→취소→다시 선택·연결 저장→연결 해제. 보존 안내와 연결 변경 번호 2→3→4 확인.
- 상세 제목/가수/원키/LIVE/티어 S/기존 실제 메모 유지. 연결 해제 후 ‘곡 미연결 녹음’ 표시. 검증 앱 종료·재시작 이후 계정 DB에서 song_id null, link_revision +2, 다른 모든 녹음 필드가 P18-05와 동일함 확인.
- 파일 명세와 녹음 저널 전체 행 불변, 기존 녹음 원본368616바이트 유지. 사용자 앱 삭제·DB 초기화·기존 실제 녹음 반복 없음.
- 커밋·푸시·필수 CI는 다음 단계.
