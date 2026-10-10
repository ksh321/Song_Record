# P18-03 녹음 후 곡 선택

## 범위·근거
- 계획서 v1.0 p00840~42: 내 곡 검색 선택기·새 곡 찾기·직접 등록 조건 연결. 많은 곡을 검색하고 외부 장애에도 입력 대기 파일 보존.
- 설계서 v1.11 p00163~65: 기존 내 곡 우선, 정상 TJ 검색 후 명시적으로 원하는 곡 없음 확인한 경우에만 직접 등록. 장애는 빈 결과가 아니며 KY 번호를 변환하지 않는다. HTML·UI_REFERENCE의 공통 새 곡 찾기/안전 영역/검색 흐름 재사용. R015/R046/R048.
- 요청/현재 관측 gpt-6.1-sol/medium 원수, 승인 끝 P18-10. P18-02 SHA8f86aae/CI38044597753 완료 후 finish02→begin03 실제 측정.

## 변경·현재 모델 별도 검토
- 입력 대기 행에서 검색 가능한 내 곡 선택기로 진입한다. ACTIVE 등록된 TJ/MANUAL 곡만 기존 account stream으로 읽고 MySong의 곡명·가수 정규화 검색을 재사용한다. 긴 목록은 lazy sliver, 키보드/작은 화면은 전체 스크롤·SafeArea.
- 실제 선택 ID의 현재 계정·ACTIVE·DRAFT·UUID를 저장소에서 다시 확인하고 capture journal에 선택 스냅샷을 저장한다. metadata DRAFT/file spec/CREATE 큐는 바꾸지 않는다. 입력 저장 완료와 실제 연결은 P18-04에 이어진다.
- 기존 새 곡 찾기 시트의 차트/검색으로 이동하고 기존 TJ/KY·직접 등록 화면 및 source 증명을 재사용한다. 현재 계정이 바뀌면 준비/저장/선택을 차단하며 파일은 유지한다.
- 명시적인 새 곡 등록 성공 후 같은 녹음 ID의 선택을 저장한다. 서버가 현재 계정 기존 곡 matchedSongId를 반환한 후보는 등록 중복 생성 없이 기존 ACTIVE 곡 선택으로 처리한다. 외부 등록/선택 실패가 native 원본이나 입력 대기를 삭제하지 않는다.
- 현재 모델 별도 검토에서 동작/계정/빈 결과와 오류 구분/직접 등록 조건/재시작 스냅샷/표준 UI를 대조한다. 전체 문서 재작성·다중 에이전트 없음.

## 검증
- 영향 검사 8 PASS: 80곡 중 가수 검색 선택, reopen 선택·파일·DRAFT/큐 보존, 외부 장애 시 직접 등록 미노출·원본 유지, 정상 TJ 빈 결과→명시적 확인→MANUAL UUID 등록·선택, 없는/휴지통/타 계정 선택 차단 및 기존 capture 회귀.
- 검사 준비 오류: 공통 fixture 추출 후 Uint8List import를 복구했다. SQLite I/O가 Flutter fake-time zone 안에 갇힌 UI fixture는 실제 I/O를 runAsync에서 수행하고 검증된 계정 stream의 최초 결과를 UI에 전달하도록 정리. 제품 계정/검색 보호 규칙을 약화하지 않음. 이 환경 오류를 제품 수정 실패와 합산하지 않음.
- 전체 flutter test --no-pub: 923 PASS, 1분37초. flutter analyze --no-pub: 0 issues, 6.3초. 검증 APK 19.9초 PASS. 현재 모델 별도 코드 검토 PASS. 실제 설치본 확인·필수 CI 대기, 아직 전체 완료 판정 아님.
- raw 로그 .local/workflow/p18-03/에 보존. 이후 필수 정보 P18-04는 완료·finish03 후 시작.

## 설치본 확인
- SM_A546S install-r Success. 기존 녹음 재사용, 곡 선택 진입→검색 빈 결과→입력 해제→검증 내 곡 실제 선택 PASS. 공통 새 곡 찾기 검색 이동→합성 외부 오류 표시 및 직접 등록 미노출 PASS. 검증 앱만 force-stop/restart 후 입력 대기1개·선택 스냅샷 유지 PASS. 실제 Cloudflare/검색 서버 장애나 비행기 모드를 검증한 것으로 확대하지 않음. 이전 녹음 원본·개인 앱 데이터 삭제 없음.
- 필수 Flutter CI 대기. 현재 모델 별도 검토 최종 PASS, 승인 끝 P18-10 유지.
