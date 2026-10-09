# P14-05 보관 상태 표시 (원수)

- P14-01~08 순차 승인·6.1-sol/medium 고정, 현재 대화 직접 구현·별도 코드 검토. 앞 P14-04 99cbe0394ea012ed868da7333a632e6caa4102f0 CI37910214758 PASS 완료 유지.
- 원본 계획서 P14-05 p730~732, 설계서 실제 Word 2.5 p203~218·8.4, R074/R075/R077, D04 actual device/UNKNOWN 규칙. UI_REFERENCE·팔레트·실제 HTML 녹음 상세의 분리 표시를 확인. HTML은 manifest 지정 LF 정규화 해시가 정확히 일치하며 Windows 원시 CRLF 해시와 구분했다.
- 변경: AccountStore.recordingStorageEvidence 읽기 전용 트랜잭션, RecordingFileStatuses/RecordingFileStatus, RecordingFileStatusCard, RecordingViewData.withVerifiedFiles 및 기존 RecordingRow 연결. 같은 계정의 현재 서버 사본/적용된 스냅샷·미전송 수정·고정 슬롯을 읽고 파일은 실제 경로/크기/해시로 확인한다. 다른 기기 보고를 현재 폰 파일로 쓰지 않는다.
- 정보 동기화·이 기기 파일·서버 파일·대기 이유 네 줄 별도 표시. ACK 이후 표시용 local payload가 남아도 서버와 같고 미전송 변경이 없으면 동기화 완료다. 고정 current+실제 STORED만 고정 보관 중, pending 교체는 파일이 STORED여도 전환 전 고정 대기. UNKNOWN이면 확인 불가/고정 상태 확인 중이며 백업 완료로 바꾸지 않는다.
- STORED의 계정/녹음·세대·크기·해시·stored_at을 대조. 최신 asset tombstone이 과거 스냅샷 보관 상태를 되살리지 않음. 보관 역할/메타정보 완료가 물리 파일 증거를 대신하지 않음. 새 DB schema·삭제·정책 변경 없음.
- 일괄 로컬: 기존831 및 새 widget1 통과, 새 DB 상태5는 시험 SQL owner 인수 누락으로 실패. 시험 설정1회 수정. 이후 스냅샷 관계 엔티티를 점 조회 API로 읽은 동작 오류1회 발견; 기존 점 조회 화이트리스트를 넓히지 않고 적용 완료 스냅샷의 계정·녹음 관계를 같은 트랜잭션에서 읽도록 수정. 다른 근본 원인과 합산/모델 상향하지 않음.
- 영향 재검증: 보관 상태6 PASS(2초), 상태/기존 music components/snapshot business 총34 PASS(9초), analyze No issues found(4.3초), diff 공백 검사 PASS. 모든 원시 로그는 Git 제외 .local/workflow/p14-05.
- 별도 현재 모델 검토: 완료 조건·diff·실행 결과·회귀/계정/UNKNOWN/삭제 증거 우선순위를 대조. ACK local payload 오인·삭제 asset 재생성 표시·pending 교체의 고정 완료 오인 지적을 해결. 사용자 고정 모델을 유지하고 다른 에이전트/모델 호출 없음. 검토 지문은 로컬 review-source.json.
- 실기 범위: 이번은 읽기/표시 변경. 실제 SQLite·파일과 widget 표시를 검사했으며 새 native/서버 쓰기/사용자 버튼 조작은 없음. 폰 설치본 실기 통과로 꾸미지 않음. 원격 Flutter 검사·APK 결과는 최종 SHA로 별도 대조한다.
- fresh 원격 base 99cbe0394ea012ed868da7333a632e6caa4102f0. 아직 최종 CI 미확인이며 P14-06~08 미착수. 직접 할 일 0건.
- 관련 개념: 정보가 서버에 전송된 상태와 실제 오디오 백업은 독립적인 상태다. 선택/대기/보관은 각각 근거가 필요하다.

## 최종 완료
- 최종 SHA 6c2b135a5e9a11dc79747c2895638bb8b216da86, 필수 CI 37914023098 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
