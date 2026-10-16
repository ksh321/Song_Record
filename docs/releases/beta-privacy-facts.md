# P25-06 개인정보 안내의 현재 사실과 미확정 항목

2026-10-15 코드·실제 제한 환경을 대조한 준비 기록이다. 개인정보처리방침의 법률 검토 완료나 전체 인터넷 공개 승인을 뜻하지 않는다.

| 항목 | 현재 확인한 사실 | 남은 조건 |
|---|---|---|
| 서버·DB | 기존 AWS 서울 `ap-northeast-2` 실험 서버의 API·MySQL·작업자. 노트북과 독립적으로 동작한다. | 실제 공개 범위와 최종 운영 제공자 표시를 맞춘다. Free plan의 기간·크레딧 한계는 별도 운영 조건이다. |
| 음원·백업 | 별도 Cloudflare R2 experiment 임시·확정·암호화 백업 버킷을 사용한다. 실제 Settings3개 모두 Asia-Pacific(APAC)/공개 개발 URL 비활성으로 확인했고 기존 개발·검증 저장소와 분리했다. | AWS 서울이라는 사실로 R2의 저장 국가까지 한국이라고 표시하지 않는다. 확인된 APAC 표시를 특정 국가 보장으로 확대하지 않는다. 실제 국외 처리 고지와 공급자 조건은 별도 대조한다. |
| 로그인 | Google·카카오 제공자 식별자로 서비스 계정을 찾는다. 현재 가입 INSERT는 제공자 이메일을 저장하지 않는다. 새 beta Android 등록·서명 설치본에서 두 로그인·재실행 유지를 확인했다. | 제공자 자체 처리·국외 처리 고지를 앱의 실제 요청 정보와 대조한다. 제공자 식별자는 이메일·이름과 다른 항목이다. |
| 콘텐츠 | 곡·녹음 메타정보·메모·태그·플레이리스트를 계정 정보 동기화에 사용하고 선택한 파일만 보관한다. 기기 원본과 서버 사본은 별도다. | 외부 ZIP·M4A 사본의 사용자 관리 책임을 유지한다. |
| 관측 | 계정·대상·작업 UUID, 종류·결과·시각·처리 시간 등을 사용한다. 원음·메모·토큰·전체 서명 URL은 관측 내용에 포함하지 않는다. USER160의30일 선택·USER161 실제 적용 허용 후 기존 AWS worker만 활성화했고 실제 주기 완료1회/삭제0/오류0·감시PASS를 확인했다. | 매분 최대500건,30일보다 오래된 행 대상이므로 장애·적체 시 지연될 수 있다. Docker 로그 용량 제한과 별개이며 백업 사본은 별도7일 정책을 따른다. |
| 탈퇴 관측 | 같은 purge의 소유자/작업 기록 제거·타 계정 행의 삭제 대상 참조 비우기·늦은 관측 재삽입 방지를 구현했다. 합성 H2·실제 MySQL·동시성·별도 검토를 거쳐 기존 AWS API/worker와 새 격리 복원용 원장 재적용에 반영했다. | 현재 개인 삭제 대기0이며 개인 계정 시험 삭제는 하지 않았다. 합성 검증과 실제 개인 삭제 실적을 구분한다. |
| 서비스 백업 | 최대7일 보관 정책과 삭제 원장·격리 복구 경로가 있다. 2026-10-16 UTC점은 음원1개/암호화/총2점이며 실제 새 격리DB 복원·파일 해시·디코딩1개/임시본 정리 PASS. 현재 서비스DB는 교체하지 않았다. | 복원본의 물리 기기 재생 미실행은 유지한다. 기존 파일0개 점의 성공이나 원본의 폰 재생을 복원본 물리 재생 실적으로 바꾸지 않는다. |
| 웹 경로 | `https://song-record-beta-ksh321.duckdns.org/privacy`와 `/account-deletion`을 기존 노트북·폰 접속 주소에만 허용했다. Google·카카오 실제 웹 소유 확인은 통과했고 개인 삭제는 접수하지 않았다. | 일반 인터넷에서 접근 가능한 공개 개인정보/삭제 경로는 아직 확정·승인되지 않았다. 준비 주소를 전체 공개 완료로 표시하지 않는다. |
| 게시자·문의 | 공개 문의 이메일 `happycompanyhaha@gmail.com`의 저장소 반영은 사용자 승인 근거가 있다. USER162에서 게시자 `노래기록 운영자` 유지를 확인했다. | 실제 최초 공개 시행일을 확정한다. 과거 작성일을 시행일로 바꾸지 않는다. |

Cloudflare 공식 [데이터 위치 문서](https://developers.cloudflare.com/r2/reference/data-location/)는 위치 힌트와 관할 제한을 구분한다. 위치 힌트만으로 특정 국가의 보관을 보장하지 않는다. 최종 개인정보 안내는 확인된 실제 설정과 이 구분을 반영한다.

현재 공개 준비본은 [개인정보 처리 안내](../runbooks/privacy-policy.md), 실제 적용·검증은 [P25-06 기록](../verification/P25-06-release-validation.md)을 따른다. 미확정 사항을 완료로 바꾸거나 기존 완료된 실제 로그인·음원 재생 결과를 되돌리지는 않는다.

2026-10-16 USER164는 본인1명 비공개 베타를 먼저 검증하도록 범위를 정했다. 현재 제한 접속·기존 본인 시험 자료로 반복 사용을 확인하며 외부 이용자 공개를 진행하지 않는다. 아래 미전송 문의와 국가 미확정은 외부 확대 전 확인 항목으로 보존하고, 이번 범위 선택을 법률 적합성 확인이나 고지 의무 면제로 해석하지 않는다.

## R2 저장 국가 확인 문의안 — 미전송

공식 데이터 위치 문서와 일반 DPA는 개별 버킷의 실제 국가를 확정하는 근거가 아니다. 아래 일반 기술 문의를 Cloudflare 공식 지원 경로에 보내는 범위만 USER163에서 확인한다. 계정/버킷 이름·키·IP·녹음·개인정보를 첨부하지 않으며 유료 지원 신청·설정 변경·새 버킷 생성은 포함하지 않는다.

Subject: R2 APAC location — country information for a privacy notice

We use private Standard R2 buckets whose dashboard location is Asia-Pacific (APAC), without a jurisdiction restriction. Before inviting beta users, we need accurate information for a privacy notice. Can you confirm which countries may store and process object data for this configuration, and whether an account owner can obtain the actual storage country of an existing bucket through an official dashboard/API or support process? We understand that location hints are best effort and do not guarantee a country. Please distinguish object storage from request handling and support access, and point us to the applicable official documentation. This is an information request only; please do not change any settings or enroll us in paid support.

담당: AI가 승인 후 공식 무료 지원 경로의 이용 가능 여부와 전송을 확인한다. 무료 제출 경로가 없으면 결제 없이 그 한계를 기록한다. 답변 전에는 대한민국 보관·특정 국외 국가를 임의 기재하거나 공개 적합 판정을 하지 않는다. 일반 DPA의 유럽 이전 조항을 한국 이용자 고지 완료 근거로 쓰지 않는다.

USER163 ‘R2 국가 문의 허용’ 후 실제 로그인된 공식 Support Portal의 Submit a case → Other를 확인했다. 무료 플랜은 billing/account/registrar 주제만 case 접수 가능하다는 화면이 나왔고 R2 기술 문의 접수는 제공되지 않았다. 따라서 이 문의는 **미전송**, 공급자 답변·국가 확정은 **없음**이다. 유료 전환·분류 위장·공개 커뮤니티 게시·새 계정 생성은 하지 않았다. 공식 포털의 기존 로그인만 재사용했으며 개인정보·버킷명·키를 문의로 보내지 않았다.
