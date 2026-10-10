# P17-05 — 곡 수정 저장과 취소

## 범위·근거
- P17-04 SHA9d0d3a5350a54f11e80184d2bccfcca9008604bf/필수CI38033301336 PASS와 완료 폰 알림 서버접수 후 원수 begin. 요청·관측6.1 Sol/medium 고정, 승인 끝P17-08.
- 원본 DOCX P17 05 직접 추출, 설계 곡수정/스냅샷 독립, UI_REFERENCE 작은 곡수정 버튼 및 공통 Key/Tier/Version picker, 기존 서버 SongEditing 허용필드·입력계약 대조.

## 변경
- 작은 곡수정 버튼→별도 화면/초안. 곡명·가수·아쉬운점·대표키·버전·곡티어를 편집하고 저장 전 원본을 변경하지 않음. picker 취소는 초안 현재값 유지, 전체 취소/뒤로가기는 저장 호출 없이 폐기. SafeArea+스크롤로 키보드/하단조작 보호.
- SongEditDraft: 원본 불변 사본·서버revision 보존, title/artist1~200자 및 note2,000자 기존 Unicode 입력계약 적용. TJ번호/소유자/녹음스냅샷을 PATCH 필드에 넣지 않음. 실제 달라진 허용필드만 기존 LocalRepository.preparePatch에 전달. 미변경 저장은 큐를 늘리지 않음.
- LocalRepository.saveCheckedEdit/AccountStore.saveEdit 선택적 expectedEffectivePayload: 기존 SQLite 저장 트랜잭션 안에서 편집 시작 당시 유효payload와 현재 값을 비교해 다른 로컬 수정/휴지통/서버 변경을 덮어쓰지 않음. 기존 일반 save 동작은 유지. 같은op 재시도는 기존hash 확인 후 종료하여 새 변경을 되덮지 않음.
- 화면은 저장 명령을 한 번 준비하고 저장 중 중복동작/뒤로가기 차단. 실패 후 같은 명령 재시도, 편집값 변경으로 op를 재사용하지 않음. 원본 변경이면 취소·다시 열도록 안내하며 계정 변경 뒤 초안 표시·저장 차단.

## 검사·검토
- 전체892 PASS(1분29초). 기존887개 유지, 새5개: 실제 SQLite 저장 전 원본 보존·6필드/null해제·TJ보존·한op재시도·stale로컬초안 거절·no-op/이전lease, 입력경계, 화면 취소/저장, 실패 재시도 동일명령, 실제AuthController 계정전환 초안숨김/저장차단.
- 초기 검사 함수오류 EDIT-TEST-VOID-AWAIT: testTextInput.hide의void를await한 코드 수정 후3 PASS. 추가 영향실행은 전체검사와native sqlite3.dll을동시에쓰려다 도구 실행불가, 코드수정 실패 횟수와 구분하고 기존 검사/빌드 종료 뒤 순차 실행한다. 테스트/기대값 삭제·약화 없음.
- 현재6.1 Sol/medium 별도 검토: 완료조건·diff·실행결과 대조. 큐/메타데이터 원자저장, local-only revision0 의존관계 유지, 기존 신규/일반 save 무변경, 취소 zero write, 필드 제한/TJ보존, 실패재시도/계정전환 guard 확인. 검토에서 오류를 입력검증/저장실패로 구분하도록 안내문 보완. 별도 AI·에이전트 호출 없음.
- 학습: 편집 중인 값과 저장된 값은 분리한다. 같은 서버revision이어도 로컬 변경이 새로 생길 수 있어 저장 직전에 원본도 대조해야 한다.

## 진행
- 최종분석·APK·실제 폰 검증·대상SHA필수CI를 확인하기 전 완료로 판정하지 않는다.

## 최종 로컬·실기
- 최종 영향9 PASS, 분석 No issues found(4.1초), APK build PASS(16.3초). 전체892 PASS 유지. 동시 sqlite파일 도구 오류는 앞 검사/빌드가 끝난 뒤 순차 영향9검사로 해소. diff --check PASS 및 현재모델 별도 검토 PASS.
- R5CW618VA1M device 확인·install-r Success·MainActivity 실행. 재잠금은 USER-074 판본2 직접 해제 회신 후 자체 앱 전면을 대조. AI가 가수/버전 초안 편집 후 취소하여 Singer/일반반주/TJ00123 유지, 가수 SavedArtist 저장 뒤 상세와 목록 반영/TJ보존 확인 PASS. 녹음 스냅샷 무변경·6필드 저장/해제·동시로컬초안 충돌은 실제SQLite테스트이며 폰으로 모든6필드를 저장한 실적으로 확대하지 않음.
- USB 화면 유지0→임시2 설정을 기록. 보안잠금 변경/우회 없음. 승인 범위 종료·중단 시0 복원해야 한다. 합성 임시DB/검증 앱만 조작, 개인DB삭제 없음.
