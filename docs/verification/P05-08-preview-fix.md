# P05-08 실기 오류 수정과 미리보기 조절 기능

사용자 실기에서 녹음 보관 설명에 double → bool? 오류 확인.
코드 검토상 ListView의 PageStorageKey를 ExpansionTile이 공유하여 스크롤 오프셋을 펼침 여부로 읽을 수 있었다.
곡 ID별 PageStorageKey를 설명 타일에 추가했다. Flutter 공식 문서도 스크롤 내부 ExpansionTile에 고유 PageStorageKey 사용을 안내한다.
https://api.flutter.dev/flutter/material/ExpansionTile-class.html

미리보기 오른쪽 위 설정에서 시스템/1.0/1.3/1.6/2.0배 글꼴, 시스템/일반/줄이기 모션을 선택한다.
설정 UI와 임시 상태는 tool/preview_accessibility.dart에만 둔다. 실제 앱 설정에는 추가하지 않는다.
앱 프로세스를 종료하면 초기화하며 시스템 설정도 변경하지 않는다.

회귀 테스트 2개: 스크롤 값 저장 후 타일 생성 및 펼침 상태 복원, 미리보기 글꼴/모션 변경 및 시스템 복원.
작성 환경에 Flutter/Dart SDK가 없어 실행은 미검증. 패치 적용과 정적 diff 검사를 수행했다.
기존 P05-08 v2 적용 후 사용하는 추가 수정 패치다. 원래 전체 패치를 다시 적용하지 않는다.
