# P18-05 — 녹음 상세와 편집

- 원수: 요청 gpt-6.1-sol/medium. 현재 모델이 직접 구현·별도 검토·통합. 원본 계획서 v1.0 p846–848, 설계 v1.11 p636–656, D06 컨디션·태그, 기존 metadata/tier API 계약 대조.
- 범위: 저장 녹음 상세와 정보 편집. 티어·컨디션·태그·메모·시각·키·버전 저장/취소. 곡 연결 변경은 다음 P18-06, 목록 정렬·필터·전체 집계는 후속 P18-07–09.

## 구현
- 기존 초기 입력 폼에 명시적 저장 후 편집 모드 연결. 초기 입력에는 티어가 없고 기존 초안 보존 동작 유지. 저장 후 편집은 저장 버튼까지 메모리에서 유지하며 뒤로/취소는 DB·전송 큐 변경 없음.
- 저장 녹음 읽기·상세·편집 진입을 현재 계정 lease로 연결. 계정 전환·삭제·동시 로컬 수정은 최신 정보 덮어쓰기 차단.
- 일반 metadata PATCH와 전용 tier PATCH를 같은 SQLite 트랜잭션에 생성. 후속 tier는 원래 followup 엔진이 선행 ACK revision을 확정하며 tier를 일반 API에 섞지 않음. 준비한 operation ID 재시도 보존.
- 파일 명세·원본·journal·song_id/link_revision 및 Song 속성 유지. D06 고정 컨디션/선택 해제/복수 태그. 신규 보관 태그는 선택 제외, 이미 연결된 태그는 보관·이름 변경 후에도 당시 스냅샷 유지·해제 가능.
- 변경 파일: account_store.dart, local_repository.dart, recording_input_screen.dart, recording_detail_screen.dart, recording_workspace.dart, recording_verification.dart, recording_edit_test.dart.

## 현재 모델 별도 검토
- 원본 완료 조건·실제 diff·API whitelist/전용 tier·순차 revision·원자성·계정 fencing·파일 보존·취소·D06 스냅샷을 대조.
- 기존 태그 이름 변경 후 녹음 수정 시 과거 이름을 덮어쓰지 않도록 보완하고 회귀 검사 추가. 연결 곡 변경은 이 편집 요청에서 금지. Song 쓰기 호출 없음.
- 시험 준비 오류(status getter 오기), Flutter fake time의 SQLite 대기, 분석 타입/정렬 지적을 각각 구분해 수정. 이 시험의 종료 대기 프로세스만 종료, 앱 데이터/사용자 DB/SDK 권한 변경 없음. 테스트 삭제·완화 없음.

## 로컬 검증
- 전체939 PASS (1분56초). 최종 영향16 PASS (초기 입력9+편집7), 최종 analyze0 (4.7초).
- ACK된 SAVED → 일반정보/전용 tier 순차 dispatch, 동일 operation 재시도 중복 없음, 오프라인 초기 저장 큐 보존, 곡 속성 불변, stale editor/계정 전환/키·태그·타입 오류 롤백, 태그 이름 변경·archive 이후 과거 스냅샷, 취소 후 metadata/queue 불변.
- APK 빌드 PASS19.5초. Git 제외 로그 .local/workflow/p18-05/. 실제 설치본 확인·커밋·필수 CI는 아직 미완료.

## 설치본 대기
- 최종 영향16·분석0 PASS. install-r Success, USB 연결 유지. Android 잠금 showing=true 및 NotificationShade 전면이므로 실제 저장/취소 실기는 미확인. USER-081 잠금 해제만 필요.
- 현재 제품 변경 미커밋 보존. P18-06 이후 미착수. 승인 끝 P18-10, 뒤 번호 우회 없음.

## 실제 설치본 검사 PASS
- USER-081 회신 뒤 SM_A546S 검증 앱 전면 확인. 티어 S 선택 후 취소 → 상세 미정 유지. 다시 S와 메모 입력 → 변경 저장 → 상세 S/입력 메모 표시. 한글 IME로 입력된 실제 문자열을 기준으로 확인(ASCII 입력 성공으로 기록하지 않음).
- 검증 앱 종료·재시작 후 계정 DB에서 tier S/메모 일치, P18-04 대비 Song payload 동일, SAVED 파일1개368616바이트와 COMMITTED journal 보존 확인. 기존 실제 녹음 재시험·다른 앱 데이터 삭제 없음. 일반정보/티어 서버 전송은 로컬 strict 계약 검사이며 실제 서버 반영으로 확대하지 않음.
- 다음 커밋·푸시·필수 CI.
