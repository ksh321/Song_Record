# 기준 자료 검색 색인

`tools/index_sources.py`가 생성한다. 원본은 수정하지 않는다.
manifest.json의 original은 저장소 루트 기준, search_copy는 이 폴더 기준이다.
외부 source 파일명은 external_name이며 실제 경로는 초기 감사 기록에 있다.
텍스트 해시는 LF 정규화, DOCX는 원본 바이트 기준이다. Word 문단 표시는 페이지가 아니다.
tasks.json은 계획서의 231개 작업·구현 내용·완료 기준·검색본 행 번호를 연결한다.
선행 조건은 plan.txt 각 단계 시작 부분에 있다. D01~D12 등 승인된 후속 결정과 반드시 함께 읽는다.
