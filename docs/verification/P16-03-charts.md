# P16-03 — 전체 배열 검증 (원수)

- D12·R087~R090·V41: ChartValidation은 받은 JSON 전체를 엄격하게 읽고 배열 아닌 값·빈 배열·부분 JSON·뒤에 붙은 문서·같은 필드 중복을 거절한다. 항목마다 정확한 원본 브랜드·문자열 ASCII 번호1~20자리·비어 있지 않은 곡명/가수200 Unicode 코드포인트 이내·유효 Unicode·중복 번호 없음을 확인한다.
- 원본 배열 순서와 정확한 번호/곡명/가수는 수정하지 않는다. position은 index+1, 원본 순위로 주장하지 않는다. 결과100개 고정 없음: 1/2/101개 검사. 기간별 동일 결과 허용, 숫자 변환·앞자리0 제거·임의 보정·오류 항목 필터링 없음.
- ChartStoredValidation은 저장된 전체 payload와 scope/provider/원본URL/STAGING 메타데이터를 대조한다. 조회만 수행하므로 실패/성공 모두 chart_item·게시 포인터를 변경하지 않는다. 개발 수집은 저장 후 이 검증을 연결하고 원자 게시를 P16-04로 이어간다. 운영 저장 미활성 유지.
- 검사: services/api/gradlew.bat -p services/api test bootJar --console plain, 전체659개 중579 성공/80MySQL 로컬제외/실패0·bootJar PASS. 검토 보강 ChartStoredValidationTests 2개와 bootJar 영향검사 PASS. 실제MySQL 필수 CI는 정확 SHA로 후속 확인한다.
- 현재 6.1 Sol/medium 직접 별도 코드 검토: 완료 조건·실제 diff·전체 배열 거절·DB 필드 크기·브랜드/기간 격리·상태 변경 없음·운영 게이트를 대조. 지적 보강: 저장된 손상 배열·메타데이터 불일치·검증의 무부작용 통합 검사 추가. 사용자 직접 조작/별도 폰 실기 없음.
- 변경: charts/ChartValidation.java, ChartStoredValidation.java, ChartCollectionConfiguration.java; ChartValidationTests.java, ChartStoredValidationTests.java, ChartDatabaseFixture.java. 학습: 개별 항목 유효성과 차트 전체 일관성을 동시에 확인해야 부분 성공을 정상 차트로 노출하지 않는다.
- 로컬·검토 PASS, 커밋/푸시·필수 CI 대기 전 미완료. 다음 P16-04.

## 최종 완료
- 최종 SHA ce7d33a169ca53ab7ec8736e7b7b5b808cebc7bb, 필수 CI 38016018389, 38016018347 PASS. 로컬·현재 모델 검토·실제 검사 근거 대조. 완료 폰 알림 서버 접수, 실제 수신 미확인. 직접 할 일 0건.
