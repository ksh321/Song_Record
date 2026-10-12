# P23-04 추가 보관 요청

- 승인: P23-08까지 원수, 사용자 지정/관측 6.1 Sol medium. 최초 begin 기준34ab6373d41a5e310ab08047b7d9661bdd117212, 요청/회신의 실제 turn 경계 유지.
- 근거: 원본 계획 p01015–p01017, R003/R123, 확정 D08. PIN_LIMIT/STORAGE_QUOTA 하나 이상, 둘 다 허용. 수량·자유 의견·가격·결제·구독 입력 없음. 부족하지 않아도 요청하며 성공 후 새 제출 가능. 한도/고정/업로드 승인은 변경하지 않음.
- API: POST /storage/requests, GET /storage/requests/me·/{id}. 기존 AccountAccess 인증/등록 기기/활성 계정 확인·IdempotentMutations·버전 없는 새 요청·계정 한정 커서를 사용. 새 제출 새 id/op, 통신 재전송 기존 id/op, 같은 id/같은 종류 다른op는200 재조회. 두 종류도 요청1건·종류별각1건. 서버가 사용량/한도/접수시각을 결정하며 클라이언트 스냅샷 입력은 거절.
- 데이터: V24 ledger/body/operation/daily. 본문·접수 시 사용량은90일 후 제거, D08 전용 영수증 식별 인덱스로 해당 common receipt만 정리. 다른 기능 영수증은 건드리지 않음. 최소 계정/id/접수시각 원장은 활성 계정 동안 보존하여 만료 ID 재전송409 STORAGE_REQUEST_EXPIRED. 운영 시작1분 뒤·이후1시간 유지 관리, 만료 본문 조회는 즉시 제외. 일간 UTC 익명 집계는 총수/종류별수/고유 계정수만 보존. 일간 고유수의 합을 월간 고유수로 간주하지 않음. 계정 삭제 연결은 후속 P23-05~08에서 검증.
- 앱: 환경/출처/계정별 FlutterSecureStorage 암호화 대기열. 각 새 오프라인 제출은새id/op로 보존, 연타는working 중 차단, 불명확한 응답·재시작은동일번호로 재전송. ACK를 기기에 기록하지 못하면 재읽기 전까지 새쓰기 차단. 손상/다른scope 기록은 자동초기화/덮어쓰기하지 않음. 계정/lease 교체에도 scope별 직렬화, 이전 결과는 폐기. 앱 시작·복귀·사용자 재전송에 연결; 서버 접수 확인 뒤 큐 제거. 만료는BLOCKED로 남기고 자동새id 생성 안함.
- 설정 보관 화면에 대기 사유 및 추가 요청 진입 연결. 실제 /storage 값은 유지하고 공간 확보/즉시 한도 증가를 약속하지 않음.
- 검사: 대기열4개(오프라인두제출/재시작/응답유실/보존/저장오류/손상/계정교체/만료) PASS; 서버StorageRequestsTests4개(반복/멱등/종류/소유권/90일/집계/페이지) PASS. 전체앱1186 PASS(2:20), analyze No issues, APK PASS. 서버 전체 {'tests': 730, 'skipped': 84, 'failures': 0, 'errors': 0} 및 build PASS. 첫 서버 전체 검사에서 새 controller 계약 대조 등록 누락1건을 확인해 실제3경로를 등록하고 재검증. 테스트/계약 경로를 줄이지 않음. OpenAPI/참조/보안/기존7wire/143경계 PASS.
- MySQL 실제 V24/스냅샷/동시두요청/고유사용자/한도불변/90일/원장 검사는 새 일회용 DB만 생성하는 기존 MySqlIdempotencyTests에 연결. 로컬 env 미설정으로 skipped, 필수 CI에서 실제 판정할 때까지 완료 아님. 사용자 개발DB를 초기화하지 않음.
- 실기: SM_A546S install-r Success. 합성HTTP 오프라인 두제출, native 암호화 기록→프로세스재시작 후 동일8자리번호prefix2개/종류 유지, 응답유실 시 서버1/대기2→재전송 서버2/대기0, 접수이력2개 확인. 전체UUID 보존은 단위검사와 코드로 대조. XML .local/workflow/p23-04/phone-offline-two.xml/offline-restart.xml/lost-response.xml/retry-received.xml. 실제 서버/개인계정 요청 접수나 실제 무선차단을 통과했다고 주장하지 않음.
- 별도 현재 모델 검토: D08·실제diff·멱등/owner/nonce/원장·익명집계/90일·기기쓰기/계정교체·불명확한결과·데이터보존·검사/설치본 대조. 현재단계 검토 승인, 필수 대상SHA CI 대기. 추가 모델·에이전트 없음.
- 학습: 같은 통신 재시도는 같은 제출이고, 사용자의 새 제출은 다른 수요다. 원장과90일 본문을 분리해 오래된 요청을 새로 집계하지 않고 익명 집계만 남긴다.
