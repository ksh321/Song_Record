# WORKFLOW-09 개발 R2 키 암호화·자동 사용

2026-10-09 사용자 최초 등록 후 Windows 계정 암호화 보관·자동 사용 승인. P12-07 완료(7305a67) 유지, 다음 제품 작업 미승인. 기존 미커밋 변경 보존.

## 변경·검토
- tools/r2_vault.py: CurrentUser DPAPI, UI 금지, dev 역할 바인딩, 암호문만 원자적 파일 교체. 현재 사용자·SYSTEM 폴더 권한. 운영/경로 조작 거절. 복호화 출력 인터페이스 없음.
- tools/r2_credentials.py: 마스킹 등록 GUI→현재 키 권한 확인→암호화 저장→저장본 자동 사용 검사. 기존 일회용 검사 유지, 빈 입력 등록 개발 키 자동 사용 및 headless --use-stored-role. Java 키 전달은 stdin, 상태 허용 목록만 기록.
- 현재 모델 직접 별도 검토: 저장·권한·역할·키 교체 실패·복호화 실패·노출 경로와 기존 검사 호환성 대조. 추가 에이전트·모델 호출 없음. 현재 계정의 다른 프로그램 접근 격리로 설명하지 않음.

## 실행 근거
- `python -m unittest discover -s tools/tests -p 'test_r2*.py'`: 14 PASS. 실제 Windows DPAPI 합성 키 roundtrip·암호문 평문 미포함·역할 교차 및 손상 거절, 저장 실패 기존 파일 유지, 자동 사용 stdin 전용·고정 보고서, 미등록 과거 PASS 무효화.
- `python -m py_compile tools/r2_vault.py tools/r2_credentials.py`: PASS.
- 암호화 파일 경로 git check-ignore 확인. 실제 사용자 키는 읽지 않음. 시험 키는 일회용 테스트 디렉터리만 사용.
- 개발 도구 변경만 해당하므로 제품 전체 검사·원격 CI 불필요. 관련 로컬 검사 및 검토로 검증.

## 남은 사용자 행동
USER-048 열린 등록 창에서 dev.worker 새 키 한 번 입력. 실제 키 등록·자동 사용 확인은 회신과 고정 상태 보고서 확인 전 미완료. 완료된 제품 실적을 되돌리지 않음.

개념: 저장 파일은 Windows 사용자 계정에 묶인 암호문이다. 자동 사용 중에는 검사 프로그램의 메모리에서 복호화하며 AI는 키가 아닌 결과만 읽는다.

## dev.worker 등록 확인·dev.api 등록 준비
- 사용자 등록 완료 회신 및 reports/dev.worker.json PASS 확인. 암호문 파일/키 내용 조회 없음.
- 사용자 dev.api 추가 등록 승인. USER-048 판본2로 역할·버튼·정상 결과 갱신. 운영 키 2개는 저장/자동 사용 대상 밖.

## 실제 등록·자동 사용 확인 완료
- USER-048 판본2 완료 회신, dev.api scope 보고서 PASS 확인. 현재 저장된 dev.api·dev.worker를 --use-stored-role로 각각 다시 실행하여 모두 PASS. 권한 경계는 API 개발 temporary만, worker 개발 두 버킷만이며 운영 버킷 거절 유지. 실제 키/암호문은 읽거나 출력하지 않음.
- 직접 할 일 0건. 개발 도구 변경만 커밋·푸시하며 제품 CI 불필요. 별도 기존 미커밋 기록은 보존.
