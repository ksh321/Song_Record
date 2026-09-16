# 공통 검증 데이터 v1

P00-08 추천 A+A+A: 공통 JSON·계약 사례·합성 M4A. 실제 사용자·곡 가사·음성은 없다. TJ 번호는 외부 API로 보내지 않는 가상 테스트 값이다.

## 사용
저장소 루트에서 `python tools/validate_fixtures.py`를 실행한다. Python 3.11 이상과 ffmpeg/ffprobe가 필요하다. 외부 API나 실제 계정에 쓰기를 하지 않는다.
앱과 서버는 `fixtures/index.json`의 파일 목록을 기준으로 동일 UTF-8 JSON을 읽는다. 복사본을 별도로 수정하지 않는다. Dart는 jsonDecode, Java는 프로젝트 JSON 매퍼로 로드할 수 있도록 원시 JSON 타입만 사용한다. 실제 두 프로젝트의 로더 연결·테스트는 P01/P03에서 구현하며 현재 실행했다고 주장하지 않는다.

## 형식과 실행 범위
- 모든 JSON은 schema_version=1. 사례는 id, kind, input, expected, refs를 가진다. ID는 전체에서 유일하다.
- 31개 구조화 사례는 Python 참조 계산으로 기대값 대조. 제품 Dart/Java 구현의 검증을 대체하지 않는다.
- 138개 integration_spec은 기존 P00-05~07 사례 전체를 시나리오/기대 결과로 옮긴 통합 검증 명세다. 자동 통합 테스트로 실행된 것이 아니다. 구현 단계에서 setup/action/assert 어댑터를 붙인다.
- entities.json은 유효한 공통 기준 데이터다. 의도적 중복·오류는 별도 사례 input에만 둔다. 필드명은 테스트 입력 모델이며 서버 DB에 직접 INSERT하지 않는다.
- index.json은 사례 ID·JSON 파일 해시·기준 결정서 해시를 고정한다. 문서 변경 시 사례 영향 검토 후 갱신한다. refs의 #R/#V/#사례 ID는 추적용 표 ID이며 HTML 앵커를 보장하지 않는다.
- Python 정규화는 이 fixture에 사용된 문자에 한해 확인했다. D02의 전체 Unicode 17.0 적합성은 앱/서버 구현 단계에서 별도 검증한다.

## 구성
contracts: 정렬·입력·날짜·분류·파일 필터 및 모든 통합 시나리오.
songs: 계정별 곡 식별·같은 번호/다른 UUID·다른 번호/같은 제목.
retention: 역할 겹침·미정 제외·동률·삭제/DRAFT 제외·키/버전별 중복 선정 방지.
backup: 로컬 1·2·3 / 서버 a·b·c의 부분 백업.
files: 무음과 낮은 음량의 440Hz 시험 신호 각각 1초 AAC/M4A, 24바이트 잘림 파일.

정상 파일의 크기/해시는 실제 계산값이다. 잘림 파일은 반드시 디코딩 실패해야 하며 해시 불일치 사례는 tone 파일에 silence의 해시를 의도적으로 주장한다. 보관 선정의 valid_file_manifest는 순수 정책용 가정으로 실제 파일 검증 성공을 의미하지 않는다.

## M4A 생성 기록
FFmpeg lavfi anullsrc(r=44100, mono), sine(frequency=440, sample_rate=44100, duration=1)와 volume=0.1로 생성. AAC 64k, 메타데이터 제거, 무음 길이 1초. 인코더 버전에 따라 바이트가 달라질 수 있으므로 생성 후 manifest의 실제 해시·크기를 다시 기록해야 한다.

## 완료 범위
공통 데이터 작성·관계/ID/해시 검사·참조 기대 결과 대조·파일 디코딩 검증 완료. 앱/서버 로더·실기·DB·인증·장애 테스트는 후속 단계이며 V/X 통과 수에 포함하지 않는다.
