# P17-08 — 표시와 빈 상태 검수

## 원본·범위
- 원본 계획서 Word XML p00826~828 직접 확인: 일반 반주·긴 제목·계정 전환·최근 녹음 없는 곡·작은 화면, V27/V39/V46/V47 및 X01~X03의 곡 화면 범위. 설계서2.1~2.2, UI_REFERENCE, 팔레트·HTML의 기존 탭/표시 규칙 대조.
- 선행P17-07 SHA870b2b478d91c324fd06f3aed1c57c77152f0fb0 / CI38039130146 PASS / 완료 알림 SERVER_ACCEPTED 후 finish·P17-08 begin. 측정 잠금 일시 충돌 재조회 후 최초 실제 조회 보존. 요청/현재 관측6.1 Sol/medium, 별도 AI·모델·Worker 없음.

## 발견·수정
- 로컬 검색의 Dart trim/toLowerCase가 서버 SongListRules/DomainOrdering의 계약 공백·NFC·ASCII A~Z만 접기와 달랐음. 같은 normalizeSongText를 검색·정렬에서 사용. 기존 한글만 합성 구현을 전체 NFC로 교체하고 저장값·표시명·TJ 식별·SR-SORT-1 그룹/숫자 토큰/최종UUID는 변경하지 않음.
- 정규화 구현은 [unorm_dart 공식 문서](https://pub.dev/documentation/unorm_dart/0.3.2/unorm_dart/nfc.html) 대조, MIT 패키지0.3.2 고정·lock SHA 보존. 네트워크/외부 검색 없이 로컬 순수 문자열 처리. 다른 의존성 업그레이드 없음.
- 별도 검증 앱의 미정곡에 긴 제목을 넣고 P17-08 표시·이동 검증 화면으로 변경. 일회용 별도 DB/앱이며 사용자 DB·파일 삭제/추가 없음.

## 검수 연결
| ID | 확인 근거 |
|---|---|
| V27 | 기존 SongRow 등록/후보 표시 검사 + 신규 긴 등록곡 NORMAL, 번호없는 상세, 후보는 외부 검색 섞지 않음 |
| V39 | app_shell_test의5개 탭·상단설정·녹음 미자동시작, 기존 P05 완료 유지. 전용오늘 탭·번호병합 없음 |
| V46 | my_songs_test 실제 SQLite ACTIVE/다른계정/휴지통/미등록 후보 제외·오프라인 로컬큐, 신규 NFC/ASCII/리터럴검색·loading/error/empty 재시도 구분 |
| V47 | SongRow·RecordingRow에 일반반주 포함, song_edit/detail 실제DB검사에서 곡 수정과 녹음 당시 스냅샷 독립. P18/P19 범위의 녹음편집/플레이리스트 화면 완료로 확대하지 않음 |
| X01 | 언어없는 모델·응답 계약, song_edit_test의별도초안·허용필드·2000자제한·저장/취소·불변TJ. 신규 키보드/큰글꼴 취소무저장 |
| X02 | my_song_pages_test 독립 서버공유fixture로5정렬/2보기·한국어/UUID동률·120개커서, my_songs_test ACTIVE/SAVED 최신시각·파일없음, 신규 결합문자검색/정렬동률 |
| X03 | 신규320×568/2배글꼴·8강조색·긴제목·모션감소·하단삭제도달·정렬시트취소·키보드취소·상세뒤로목록스크롤복귀. 기존 공통시트 하단SafeArea/테마/탭 접근성 유지 |

## 영향 검사·오류 판정
- 신규6개 PASS. 최초 신규검사2실패는 NBSP가계약trim에포함된다는 테스트기대값오류와 긴제목아래NORMAL 행이 lazy ListView에서 아직생성되지않은검사스크롤누락. 계약함수·실제widget구조대조 후 NBSP trim과FEFF미trim을각각검사하고 실사용처럼스크롤하여같은NORMAL기대값검사. 제품결과를맞추기위한약화없음. 서로다른검사원인으로실패횟수합산안함.
- 현재 모델 별도 검토: 실제diff·원본완료기준·정렬공유fixture·계정lease/늦은구독취소·스냅샷불변·무외부검색·저장원문보존 대조. 최종전체검사와설치본/CI결과확정전완료아님.
- 오프라인 검증은 현재 인증된 계정에서의 로컬 조회/검색이다. AuthController.restore의앱새시작인증확인은기존P06 API정책이며 이번곡화면검수를콜드스타트오프라인인증통과로확대하지않는다. 배포통합P26에서인증복구/오프라인앱재시작을별도확인한다.
- 학습: 같은글자가조합형식으로다르게저장될수있어검색/정렬만동일규칙으로정규화하고사용자원문은보존한다. 긴화면의행은스크롤후검사해야하며부재와아직미생성을구분한다.

## 최종 로컬 검사·별도 검토
- flutter test --no-pub --reporter expanded: 전체908 PASS(1분33초). 신규 영향6 PASS. flutter analyze --no-pub: No issues found(5.2초). 별도 searchVerification APK 빌드PASS(24.2초). 로그·검증소스/산출물해시는Git제외 .local/workflow/p17-08에보존.
- 첫분석의import순서/중괄호/테스트빈List타입표기5건은동작무변경정리후영향6·분석을다시통과. 전체회귀반복없음.
- 현재6.1Sol medium 별도검토PASS: 실제diff와V/X각근거대조,원문보존·NFC정렬/검색일치·ASCII만fold·실제SQLite/서버fixture의계정/상태/커서검사대조. UI본체변경없이기존작은화면/큰글꼴/시트안전영역통과. 실제설치본·CI대기.

## 설치본 검수
- R5CW618VA1M/SM_A546S에 별도APK install-r Success·MainActivity 실행. 최초 dump null root는 화면 깨움 후 정상 own-app XML 확인, 통과로 추정하지 않음.
- AI 실제 확인 PASS: 긴 제목 전체 줄바꿈(스크린샷 시각확인 포함), 일반 반주·TJ 번호 없음·대표미지정/최신녹음없음/최저티어없음·자동보관0개, 스크롤 후 연결녹음0개·하단삭제도달, 상세뒤로 동일목록복귀,5개정렬시트와취소후최근추가순/3곡유지, 계정B전용1곡/A곡미표시→A복귀.
- 작은320×568/2배글꼴/8강조색/키보드/모션감소는위젯검사, 실제기기는기존폰표시설정이다. 합성일회용DB/검증앱이며실제서버계정로그인·타기기·파일서버보관실적이아님. 현재폰설정 stay_on_while_plugged_in 원본0/현재0 유지, 추가사용자실기불필요.
- raw XML/스크린샷/소스/APK 해시근거는 .local/workflow/p17-08에 Git제외 보존. 현재모델검토·로컬·실기통과 후 정확한SHA필수CI확인만남음.
