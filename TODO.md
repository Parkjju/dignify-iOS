# iOS TODO

작성 2026-08-07. **2026-09-30 정리 — 완료된 P5 작업·P6·P7을 맨 아래 이력으로 접었다.**
현재 스토어 버전 1.3.1(빌드 28, 2026-10-30 확인). 다음은 1.3.2(빌드 29) — 재방문 푸시 2종. 테스트 끝, **UX Writing 확정 문구 반영 전엔 심사 제출 금지**. **기획 댓글 반영 범위도 제출 전에 정할 것**(재방문 푸시 5).

> 🎨 **디자인 반영할 것은 `../dignify-design/app-changes.mdx`가 정본이다**(배포본: 디자인 Storybook 「가이드 › 앱 반영 목록」).
> 시안 버전별로 화면 id · AS-IS · TO-BE · 앱 파일 위치가 적혀 있다. 아래 버전부터 차례로 반영하고, 끝나면 그 버전 상태를 「반영됨 (iOS x.y.z)」로 바꾼다.
> 수치·동작은 각 항목이 가리키는 `../dignify-design/components/<이름>/<이름>.md` 명세를 따른다.

## 🎨 푸시알림 기획 1.0 — 광고성 동의 UI 교체 · 1.3.2 초안 대체 (2026-11-17 등록)

정본은 `../dignify-design/app-changes.mdx` 「푸시알림 기획 1.0」 — 맨 위 **「광고성 알림 노출 규칙 — 정본」**(언제·어디서·어떤 세션에) + 항목 1~10(AS-IS·TO-BE·수치). 시안은 디자인 Storybook **Screens › 6. 광고성 알림**(동의 흐름 전부를 한 프로토타입으로). Figma 화면 플로우는 설계서와 부딪혀 참고만 한다.
**아래 「재방문 푸시 2종 › 5. 기획 댓글 반영」의 동의 팝업 요건·결과 통지 토스트·마이 › 알림 항목은 이 절이 대체한다.** 서버 몫은 `dignify-backend/TODO.md` P1-c, 안드로이드는 같은 이름 절(1:1로 같이 갈 것).

**노출 규칙 (정본 그대로)**
- [x] A 첫 실행 팝업(`FeedView` `showAdConsent`·`offerAdConsentIfNeeded`): 조건에 **좋아요 1곡 이상** 추가, 제목 아티스트 = 가장 최근 좋아요한 곡의 아티스트. 「나중에」 = **닫기만**(지금의 `PUT false` + 통지 삭제) + **7일 뒤 다시** — `didOfferAdConsent`(1회) → 마지막 노출 시각으로. 미응답 판정은 서버 `adPushConsentAt`(P1-c에서 내려 줌)
- [x] B 좋아요 시점: 가운데 팝업(`hypeOfferArtist`) → **바텀시트**(ConsentSheet 신규). 재질문은 「같은 아티스트 두 번째 좋아요」(`hypeOfferArtists`) → **「일주일 동안 안 보기」 7일**로
- [x] C 야간 동의 팝업 **신규**: 이번 주 특집 5/5를 넘긴 직후 다음 곡 위에. 조건 = 광고성 동의 + 기기 권한 허용 + 야간 미응답. 아니요도 응답(false 저장 + 토스트). **서버 P1-c 야간 필드 배포 뒤**
- [x] 세션: A·B·C **실행당 하나**(`AppSession.didShowPermissionPopup` 공유), 우선순위 A → B → C, 동의를 받은 실행엔 C 안 묻기
- [x] 동의 팝업·시트는 **버튼으로만 닫힘**(`DSPopupHost(onDismiss:)` 딤 탭 끄기), 닫아도 피드 곡 그대로
- [x] 「알림 받기」 순서: 동의 저장 → 기기 권한 「설정 전」이면 OS 권한 팝업 → 결과 토스트. 거부 상태면 **설정 앱을 자동으로 열지 않는다**(`acceptAdPush`의 `openSettingsURLString` 분기 삭제)

**화면 (app-changes 항목 번호)**
- [x] 1 팝업 딤 55% → 35% `DSColor.dim`(`DSPopup.swift`, 앱의 팝업 전부)
- [x] 2 피드 배경 blur 28·brightness·saturation → **blur 38 + 검정 45%**(`backgroundArtwork`)
- [x] 3 상단 줄 좌우 16 → 20 · **아트워크 좌우 20**(`TrackCardView.artworkSide`의 `- 48` → `- 40`, 픽 재생 포함) · 모드 알약 「좋아요 따라가는 중」
- [x] 4 P02 Popup 동의형(마크 없음, 「나중에 | 알림 받기」 가로, 좌우 20, 제목 18 bold 아티스트만 brand)
- [x] 5 ConsentSheet 신규(알림 미리보기 그림 = 아이콘 자리에 좋아요한 아티스트 자켓, 동의 문구 한 줄)
- [x] 6 **Toast 신규**(공용 — `PickListView.showToast` 참고) → `MainTabView`의 `DSNoticePopup` 결과 통지 대체. 「알림 설정을 저장했어요」 + 「Dignify의 (야간) 광고성 정보를 YYYY-MM-DD에 동의했어요 / 거부했어요」(마침표 없음, 2026-11-17 확정)(날짜 = 서버 `processedAt`)
- [x] 7 P14 야간 팝업(4번과 같은 모양, 「아니요 | 알림 받기」)
- [x] 8 앞 구간 배지 m = 실제 곡 수(최대 10) · 앞 구간 배지 위치 safe+56 → **safe+90**(모드 알약 아랫선에서 48, 픽 배지 포함, 2026-11-17 Figma 실측) — `FeedView.contextBadge` 상단
- [x] 9 마이페이지 배치(제목 title1 24, 닉네임 위아래 20, 행 50, 구분선 위아래 12, 토글 설명 「좋아요한 곡과 비슷한 곡이 나와요.」)
- [x] 10 마이 › 알림(`NotificationSettingsView`): 야간 토글 추가, 토글마다 결과 토스트, 실패 = 토스트(빨간 글자 삭제), 광고성 끄면 야간도 꺼짐, 광고성 꺼진 채 야간 탭 = 「먼저 동의」 토스트, **기기 알림 권한 「설정 전」이면 셀 무반응**(지금 `requestPushAuthorization(source: "settings")` 호출 삭제)
- [x] 문자열: ko 값은 시안 문구, en은 뜻에 맞춰. 카탈로그에 파일로 넣고 Xcode 껐다 켜기
- [ ] 끝나면 `../dignify-design/app-changes.mdx` 「푸시알림 기획 1.0」 상태에 「반영됨 (iOS x.y.z)」

**2026-11-17 코드 들어감(빌드·실기기 전).** 서버 P1-c는 `1bce18b`로 main에 있다(`adPushConsentAt`·`adPushNightConsent`·`PUT /users/me/push-consent/night`).
- 코드 메모: 동의 상태는 `AppSession.adPushAnswered`(서버 `adPushConsentAt` != null)·`adPushNight`(nil = 미응답)·`acceptedAdPushThisLaunch`, 실행마다 `applyConsent(from:)`. 토스트는 `AppSession.toast` → `MainTabView` 오버레이(`Core/DesignSystem/DSToast.swift`). 팝업 모양은 `DSConsentPopup`(`DSPopup.swift`, `DSPopupHost(onDismiss: nil)`이면 딤 무반응), 시트는 `Features/Feed/ConsentSheet.swift`(높이 상수 402, `shareSheetHost` 옆 노드). 업데이트 소식 시트 표시는 `session.showingWhatsNew`로 옮겼다(닫히면 A)
- 기록 키: `adConsentOfferedAt`·`hypeOfferMutedAt`(1970 기준 초). `didOfferAdConsent`·`hypeOfferArtists`·`FeedView.shouldOfferHypePush`는 삭제
- 마이페이지 제목 24는 네비바를 숨기고 직접 그린다(`.toolbar(.hidden)`, 뒤로 버튼 이름용으로 `navigationTitle`은 남김). 위 여백은 safe area + 20 — 실기기에서 글자 위끝 84 근처인지 볼 것
- 피드 카드의 아래쪽 검정 그라데이션(`feedSlot`, 글자 대비용)은 남겼다. 배경 자체만 blur 38 + 검정 45%
- **계측 신규(안드로이드도 같은 이름으로):** `ad_night_consent_shown/accepted/declined{source: curation_end|settings}`. 좋아요 시트 「일주일 동안 안 보기」 = `push_optin_declined`·`ad_consent_declined{source: hype}`. 첫 실행 「나중에」도 `ad_consent_declined{first_run}`(서버엔 안 올림)
- 마이 초기화 행: 디버그 빌드는 항상, TestFlight(`AppTransaction` `.sandbox`)는 **버전 글자 5번 탭**으로 열린다(심사 빌드도 `.sandbox`라 숨김). 행은 서버에 false를 보내 `adPushConsentAt`이 남는다 → A·C를 다시 보려면 어드민 「광고성 동의 초기화」(backend `b9af0f9`)
- 테스트 순서 정본: 컨플루언스 「광고성 알림 동의 테스트 시나리오 (iOS 1.3.2 TestFlight)」(19595265)
- [x] Xcode 껐다 켜고 빌드(새 파일 `DSToast.swift`·`ConsentSheet.swift`, 카탈로그는 파일로 고침 — 새 키 19개, 값 변경 2개, 안 쓰는 키 7개 삭제)
- [ ] 기기 확인 — A·C 확인 완료(2026-11-17), **B와 마이 › 알림 남음**: A(코치마크 직후·업데이트 소식 닫은 직후, 「나중에」 → 7일 전엔 안 뜸) / B(실행 2회 이상, 좋아요 → 다음 곡, 「일주일 동안 안 보기」) / C(특집 5/5 넘김, 동의+권한 허용 계정) / 한 실행에 하나 / 딤 탭 무반응 / 토스트 위치(탭바 위 8)·3초 / 마이 › 알림 야간 토글·「먼저 동의」 토스트·설정 전 셀 무반응

**기획 확인 대기(코드 막지 않음, 문구만 바뀔 수 있음):** 야간 시간 문구 「오전 8:00 ~ 오후9:00」(실제 21~08시) · 시트 동의 문구 · 주간 추천 곡 수 5 vs 최대 10 · 시트 버튼 색(설계서 brand / 원본 검정)

## 🎨 seed_picker_opened 1.0 (마이 「추천 기준 곡」 개편) · 1.3.1 빌드 27에 합침 · 실기기 확인 완료(2026-10-20)

정본은 `../dignify-design/app-changes.mdx` 「seed_picker_opened 1.0」 1~8번(AS-IS·TO-BE·수치 전부 거기). 1.3의 마이 쪽(가로 CrateCell·비활성·커버 탭 스크롤)을 이 버전이 덮는다.
**장르(3번, 1번의 「· 장르」)는 서버 `dignify-backend/TODO.md` P2-c가 먼저다.** 서버가 오기 전엔 장르 칩·장르 표시만 숨기고 나머지를 먼저 낼 수 있다.

1차 — 서버 없이:
- [x] 1. 세로 목록: `SeedPickerView.swift`에서 `HypeCollection` 대신 `LazyVStack`, 행 = 커버 52 · 제목 / 아티스트 · 체크 원 24(고르면 brand 원 안 흰 체크 **12**), 행 탭 = 고르기/풀기. 「좋아요한 곡 N」. 하입 기록·디깅 프로필의 `HypeCollection`은 손대지 않는다
- [x] 2. 제목 `title2` 두 줄 + ⓘ → 말풍선(Tooltip 신규, 2초 뒤 페이드·바깥 탭 닫힘). 기존 캡션 삭제. 「따라가기」 꺼짐 안내·저장 실패 문구는 그대로
- [x] 4. 3곡 다 고르면 안 고른 행 비활성(커버 흑백 40%, 글자 60%, **원은 60%로 남김**) + 탭 → 확인형 팝업 「선택한 곡 중 1개를 해제해 주세요 / 3개까지 선택할 수 있어요」
- [x] 5. 트레이: 지면 `background` + 그림자, 남은 칸 수 안내(0·1·2·3곡 문구 — 3곡은 「3곡을 다 골랐어요」), **커버 탭 = 빼기**(1.3 「커버 탭 → 스크롤」 삭제). 공용 `Onboarding/SeedTray.swift`라 온보딩 쪽 동작이 안 바뀌는지 확인
- [x] 6. 저장 활성 규칙은 지금 그대로(`selected != savedSelection`, 0곡 저장 허용)
- [x] 7. 빈 화면(EmptyState 신규): 아이콘 원 + 문구 2줄 + 「곡 찾으러 가기」 → 피드 탭
- [x] 8. 팝업 모션 — 앱 팝업 전부: `Features/Feed/PushOptInPopup.swift`의 `.transition`을 딤(0.25s 페이드)·카드(scale 1.2→1 + 페이드, `.spring(duration: 0.3, bounce: 0)`)로 나눔, 닫힘 0.2s 페이드. 새 확인 팝업도 같게. 동작 줄이기면 페이드만
- 1차 코드 메모: 팝업 공용 틀은 `Core/DesignSystem/DSPopup.swift`(`DSPopupHost` 딤·카드 모션, `DSNoticePopup` 확인형). 「좋아요한 곡 N」은 `GET /users/me/stats?range=all`의 `hypeCount`(못 받으면 줄 숨김). `HypeCollection` 선택 모드·`focusedId`는 쓰는 곳이 없어져 삭제
- [x] 새 문자열 10개 + 「아직 좋아요한 곡이 없어요」(2026-10-20 카탈로그에 파일로 넣음, 옛 제목·캡션 키 2개 삭제)
- [x] Xcode 껐다 켜고 빌드
- [x] 실기기: 3곡 꽉 참 → 회색 행 탭 팝업 → 하나 풀면 비활성 바로 풀림 / 다 빼고 0곡 저장 → 피드가 최근 좋아요 3곡 기준으로 / 좋아요 0 계정 빈 화면 → 피드 이동

2차 — 서버 P2-c 배포 뒤:
- [x] (2026-10-20 연동, 서버 `8423757`) 3. 장르 칩(FilterChip 신규, 「전체」 + 좋아요한 장르만 많은 순, 장르 바꿔도 고른 곡 유지) · 행의 「아티스트 · 장르」 · 「좋아요한 곡 N」이 장르 곡 수로
  - **서버 배포됨 (2026-10-20 `8423757`, 리비전 00083):** `HypeItem.genreId`·`genreName`(로케일 ko/en) · `GET /users/me/hypes/genres` → `{total, genres:[{genreId, genreName, count}]}`(많은 순, total = 장르별 합) · `GET /users/me/hypes?genreId=`(커서 그대로, 없는 장르면 빈 목록). 스펙은 `dignify-backend/openapi.yaml`
- 2차 코드 메모: 칩·「좋아요한 곡 N」은 `GET /users/me/hypes/genres`(진입 때 한 번), 목록은 `GET /users/me/hypes?genreId=`(`.task(id: genreId)`라 칩을 빠르게 바꾸면 이전 요청 취소). 트레이 커버는 장르를 오가며 받은 곡(`seen`)에서 그린다. 1차의 `/users/me/stats` 호출은 뺐다. 「전체」 문자열 추가
- [x] 실기기: 장르 바꿔도 트레이 그대로 / 다른 장르에 있는 고른 곡도 커버가 보임 / 칩 숫자 = 「좋아요한 곡 N」 / 영어 로케일이면 장르 이름 영어
- [x] `../dignify-design/app-changes.mdx` seed_picker_opened 1.0 상태에 「반영됨 (iOS 1.3.1)」

## 🎨 1.3.1 (빌드 28) — feed_coachmark 1.3 + 계측 변경 + seed_picker_opened 1.0 · 2026-10-20 심사 제출(`6307fcf`까지)

**1.3.0(빌드 25)은 `55ae9d8`~`7c7b56d`(1.0~1.2)로 이미 올렸다. 아래는 그다음 1.3.1로 나간다.**
버전·빌드 번호(앱·위젯)와 앱 안 노트(`Changelog` 1.3.1, 문자열 2개), 스토어 노트(`marketing/appstore/copy.md` 1.3.1 절)까지 들어갔다.

**코드는 다 들어갔다** (상세는 디자인 문서 1.3 절 · `../09_analytics_queries.md` 규칙 18·B-2·A-14):
- 디자인: 곡 고르기 3곡 다 고르면 나머지 비활성 + 고른 곡 트레이(온보딩 `SeedPoolPickerView`, 마이 `SeedPickerView`, 공용 `Onboarding/SeedTray.swift`), 마이 「사용법」 삭제. 새 문자열 3개를 카탈로그에 파일로 넣었다(Xcode 껐다 켜고 빌드)
- 계측(안드로이드와 같은 이름): 픽 안 청취는 `source: "pick"`(이전 빌드는 `"feed"`에 섞임) · `push_opened` 삭제 → `app_opened_push{type, push_id}`·`app_opened_now_playing`·`app_opened_link`·`app_opened_direct`(`App/AppOpenTracker.swift`, 앞으로 나온 뒤 2초 판정). `push_id`는 서버 배포(2026-10-19) 전 알림이면 키째 빠진다. Live Activity `widgetURL(dignify://now-playing)`, `dignify` URL 스킴 등록. `app_opened_link`는 입구가 없어 지금은 0

- [x] 빌드 확인(새 파일 `AppOpenTracker.swift`·`SeedTray.swift`, 위젯 `widgetURL`)
- [x] 실기기: 꺼진 상태·백그라운드 각각 푸시 탭 → `app_opened_push` / 잠금화면 Live Activity 탭 → `app_opened_now_playing` / 아이콘 → `app_opened_direct` / 제어 센터 내렸다 올림 → 아무것도 안 찍힘
- [x] 실기기: 어드민에서 본인 uid로 지정 발송 → 탭 → PostHog `app_opened_push`의 `push_id`가 발송 이력 값과 같은지
- 알림 탭을 서버에도 직접 알린다: `POST /push/{pushId}/opened`(인증 헤더 없이, `AppDelegate.reportOpened`). 어드민 발송 이력의 **열람·열람률**이 된다(서버 `fbd95ff`). PostHog와 달리 앱을 보던 중 누른 배너도 센다
- [x] 실기기: 지정 발송 → 탭 → 어드민 발송 이력 그 행의 열람이 1 오르는지(2026-10-19 확인)
- [x] `../dignify-design/app-changes.mdx` 1.3 상태에 「iOS 1.3.1」 적기

**빌드·실기기 확인 끝(2026-10-19). 2026-10-20 seed_picker_opened 1.0을 합치며 빌드 26 → 27(→ 28: 추천 기준 곡 ⓘ 간격), 앱 안 노트·스토어 노트(`marketing/appstore/copy.md`)를 3줄로 다시 썼다. 남은 건 아카이브·제출.**

## 🚀 1.3.0 (빌드 25) — 2026-10-12 심사 제출(`7c7b56d`까지), 출시됨. feed_coachmark 1.0~1.2

스토어 문안(설명·프로모션·노트)은 하입 → 좋아요로 바꾸고 fluent-korean 지침으로 다듬어 `marketing/appstore/copy.md`에 있다.
스크린샷은 다른 세션에서 새로 뽑았다. 앱 안 1.3.0 노트(한국어)는 다듬기 전 문구라 스토어 노트와 조금 다르다.

- [x] 심사 결과 확인 → 출시되면 맨 위 「현재 스토어 버전」 줄과 메모리 갱신
- [ ] 출시 후 PostHog: `coach_shown`/`coach_finished`가 이제 `screen: "feed"`만 남는다. picks·mypage·seed_picker로 나눠 보던 인사이트를 정리한다

- [ ] 1.3.1 출시됨(2026-10-30 확인). 남은 것: 프로모션 텍스트·설명 불릿을 `marketing/appstore/copy.md` 1.3.1 문구로(심사 없이 수정 가능)

## ⏳ 나중 (App Store Connect 개편분, 2026-10-12 점검)

- [ ] 헤더·검색결과 크리에이티브 에셋(iOS 27 이상에서만 보임, 21:9 / 3:2, 영상 가능). 승인된 에셋은 출시된 버전에 새 빌드 없이 게시할 수 있다
- [ ] iPhone Duo 대응: 2027-04부터 Duo 스크린샷이 필수다. 그 전엔 Xcode 27.1로 빌드하지 말 것(Duo 대응 빌드가 된다)
  - 2026-10-20 깨지는 곳만 코드로 대응(`FeedView.swift`): 아트워크 한 변이 폭 기준이라 펼침(951×669)에서 903 정사각형이 위아래를 뚫던 것 → `TrackCardView.artworkSide`가 높이도 본다(일반 아이폰은 그대로). 카드·검색 줄·검색 패널이 좌우 inset을 따로 뺀다(접힘: 오른쪽 세로 막대 84). 펴고 접을 때 inset을 다시 읽는다(`body`의 `onGeometryChange`)
  - 일부러 안 한 것: 온보딩 3열 그리드는 펼침에서 타일이 커지지만 스크롤돼서 안 깨진다. 안쪽 화면 사이드바(`.defaultTabBarPlacement(.sidebar)`)·두 칸 배치는 기능 추가라 뺐다
  - [ ] Xcode 27.1 Duo 시뮬레이터(Device Hub)로 접힘·펼침·펼침 세로·Split View 왼쪽/오른쪽에서 피드·픽 재생 확인. 특히 펴고 접는 순간 카드 위치가 따라오는지(창 inset이 크기보다 늦게 바뀌면 한 번 어긋난다)

## ⏳ 재방문 푸시 2종 — 신곡 알림 · 주간 추천 (2026-10-29 확정 반영)

정본은 Confluence 03. Dev 「재방문 푸시 기능 2종: 기능 명세」(13074433)와 하위 「개발 참고: 신곡 알림」(13008898)·「개발 참고: 주간 추천 푸시」(12681240).
**Claude Docs 초안(Rf2t9FTE…)과 이 절의 10-27판(`didOfferPushHype`)은 낡았다 — 아래로 대체.** 서버 몫은 `dignify-backend/TODO.md` P1-b.
세 푸시(큐레이션·신곡·주간) 모두 **광고성**이다. 서버 동의 필터는 이 앱의 동의 팝업이 나간 뒤에 켠다 — **이 절 0이 서버보다 먼저 나가야 한다.**

**2026-10-30 코드 들어감(빌드·실기기 전).** 서버 `2866463`으로 `GET /feed/tracks?ids=`(알림 곡 조회)와 `/users/me`의 `adPushConsent`가 붙었다 — 앱이 쓰는 계약이 전부 배포됐다.
- `/feed/tracks`의 `isHyped`는 항상 false다. 발송 뒤에 좋아요한 곡은 카드에 빈 하트로 보인다(누르면 409 → 성공 처리라 동작은 맞다)

### 0. 광고성 정보 수신 동의 (서버 P1-b 0 배포됨 `489f43d`)

- [x] 첫 실행 동의 팝업: `seenFeedCoach`가 true로 바뀌는 시점에 1회(세 푸시 공통). 수락 → `PUT /users/me/push-consent` + 시스템 권한 요청 + 결과 통지. 기록 `didOfferAdConsent`(신규 `@AppStorage`)
  - 코치마크를 이미 본 기존 유저(예전 권한 거부 포함)는 업데이트 후 앱 실행 시점에 1회
  - 권한 상태별: `.notDetermined` → 시스템 요청 / `.denied` → 설정 앱(`openSettingsURLString`) / `.authorized` → 동의만
  - 문구에 **「광고성 정보 수신동의」 명시**("혜택 알림"·"마케팅"이면 무효)
- [x] 큐레이션 완주 팝업 삭제: `offerPushIfNeeded()`(`FeedView.swift:1079`)와 호출부(1035). `didOfferPush` 키는 안 써도 지우지 않음
- [x] 결과 통지(14일 내): 동의·거부·철회 처리 후 「귀하가 요청하신 Dignify의 광고성 정보 [수신동의/수신거부]가 YYYY-MM-DD에 처리되었습니다.」 — 날짜는 서버 응답값
- [x] 수신거부 액션: `UNNotificationCategory("AD_PUSH")`에 「수신거부」 등록 → `POST /push/{pushId}/opt-out {deviceToken}`(인증 없음) → 결과 통지. 이 액션이면 피드 안 건드림
- [x] 마이페이지 알림 설정 화면(신규): 광고성 수신 토글(서버 값) + OS 권한 상태, `.denied`면 「설정에서 켜기」
- **게스트에게는 동의 팝업을 띄우지 않는다**(2026-10-29 확정). 첫 실행 팝업도 `authState == .signedIn`일 때만 — 게스트로 코치마크를 끝낸 유저는 로그인 후 첫 실행 때 뜬다(`didOfferAdConsent`가 없으므로)
- 계측 `ad_consent_shown/accepted/declined{source: first_run|hype|settings}`
- 코드 메모: 팝업은 `FeedView.offerAdConsentIfNeeded`(피드 받은 직후 + `finishCoach`). 첫 실행 「나중에」도 `PUT false` + 결과 통지. 통지는 `AppSession.consentNotice` → `MainTabView` 확인 팝업 한 곳. 「수신거부」는 앱을 안 열고(`AppDelegate.optOut`) 결과를 **로컬 알림**으로 통지한다(앱이 안 떠 있을 수 있다). 기기 토큰은 `apnsDeviceToken`에 둔다. 게스트로 코치마크를 끝내고 로그인한 실행엔 안 뜨고(`signedInFromGuest`) 다음 실행에 뜬다

### 1. 좋아요 직후 팝업 「혁오 신곡이 나오면 알려 드릴까요?」

- [x] 조건: 로그인 + `pushAuthorizationUndecided()` + `launchCount >= 2`(신규 `@AppStorage`) + 세션 플래그 꺼짐 → 좋아요 후 **다음 카드 전환 직후**(`onChange(of: currentIndex)`, `burst()`와 안 겹치게). 광고성 동의가 없으면 여기서 같이 받는다
- [x] 겹침 7건(문서 표): 코치마크 / 로그인 시트·`pendingSignIn` / 좋아요 모션 / 첫 실행 동의 팝업 / `maybeAskReview()` guard / 온보딩 곡 고르기(`SeedPoolPickerView` 좋아요 제외) / 잠금화면 `ToggleHypeIntent`(`audio.isBackground`면 제외). 업데이트 소식 등 시트가 떠 있으면 건너뜀
- [x] 「나중에」 후 재질문: 같은 아티스트 곡을 두 번째 좋아요할 때 1회 — `hypeOfferArtistIds`(`@AppStorage` JSON)
- [x] 세션 중복 방지 플래그는 `AppSession`(메모리). 픽 작성·아티스트 요청 경로도 같은 값을 본다. **팝업별 플래그를 공유하지 말 것**(공유하면 한쪽 본 유저에게 다른 쪽이 영영 안 뜬다)
- [x] `PushOptInPopup` 재사용, 계측 `push_optin_*{source: "hype"}`
- 코드 메모: 세션 플래그 `AppSession.didShowPermissionPopup`(리뷰 요청 guard·픽 팝업도 봄, 아티스트 요청은 올리기만). 아티스트는 피드 응답에 id가 없어 **이름**으로 센다(`hypeOfferArtists`, 개행 join). 실행 횟수 `launchCount`는 `AppDelegate` didFinishLaunching
- [x] 1.0.6 "권한 요청을 첫 하입 직후로 이동" 기록이 지금 코드에 없는 이유를 git 이력으로 먼저 확인
  - `c5fb442`(2026-08-04)에서 뺐다. 그때는 하입하는 순간 **시스템 팝업을 바로** 띄웠고, 곡을 저장하는 손 위로 알림이 떠서 걷어냈다. 이번 설계(다음 카드로 넘어간 뒤 자체 팝업 → 수락하면 시스템 팝업)가 그 문제를 피한다

### 2. 알림 탭 → 피드 앞 구간 (신곡·주간 공통)

- [x] `AppSession.pendingCurationOpen`을 `{type, trackIds}` 대기 항목 하나로 일반화. **탭(`didReceive`)마다 앞 구간 교체**, 나중 탭이 덮어씀. **포그라운드 수신(`willPresent`)은 피드 재구성 안 함**
- [x] `new_release`: 신곡 전부 → 끝나면 `GET /feed/related?seeds=`(신곡 구간에서 좋아요한 곡, 없으면 신곡 중 무작위 1곡 — 신곡 벡터는 운영에서 보장, 10-29 확정) → 연관 구간에서 **연속 5번 넘기면** 평소 피드(좋아요·끝까지 듣기면 카운터 0)
- [x] `weekly_pick`: 5곡 → 평소 피드. 앞에서 본 곡은 `upcoming(after:from:)`로 빠짐
- [x] 곡이 내려갔으면 남은 곡만, 없으면 조용히 평소 피드
- [x] 계측 `source(for:)`(`FeedView.swift`) 확장 — 지금은 `curationCount` 범위면 무조건 `curation`. 앞 구간 출처를 기억해 `new_release`·`new_release_related`·`weekly`·`curation`

- 코드 메모: `curationCount` → `prefixCount` + `prefixSource`, 연관 구간은 `relatedRange`. 연관 곡은 마지막 신곡에 왔을 때 + 신곡 구간에서 좋아요할 때마다 다시 받는다. 끝까지 듣기 = 체류 28초 이상. 다시 받은 뒤 첫 카드도 `logTrackViewed`를 탄다(전엔 강제 재로드 뒤 첫 곡 `track_viewed`가 빠졌다)

### 3. 알림 미허용 유저도 신곡 받기 (안 A)

- [x] 로그인 유저가 앱을 열면 `GET /feed/new-releases`를 피드 앞에. 본 신곡 id는 기기 기록(`seenCurationSet` 방식, 5초 미만 스킵은 서버가 못 거름)
- [x] 카드에 「좋아요한 아티스트의 신곡」 표시 — 큐레이션 배지 자리 재사용이 최소(시안 대기) — 배지 「좋아요한 아티스트의 신곡 n/N」, 주간은 「이번 주 추천 n/N」으로 우선 넣음. 앞 구간은 한 번에 하나(알림 탭 > 안 본 신곡 > 큐레이션)
- [ ] 구간 뒤 「다음 신곡도 알림으로 받기」 제안 — `.denied`·동의 false면 무엇을 켜야 하는지 안내

### 4. 마무리

- [ ] 수신 처리 빌드 번호를 서버 `meetsMinBuild`에 알려 줄 것(이전 빌드엔 광고성 푸시 미발송)
- [ ] ⚠️ **심사 제출 전 필수 — UX Writing 확정 문구 반영.** 문자열(동의·좋아요 팝업·결과 통지·설정 화면·수신거부 액션·신곡 배지·What's New 1.3.2 4줄)은 전부 초안이다(2026-10-30 카탈로그에 파일로 넣음). 확정되면 `Localizable.xcstrings` 값만 바꾸고 Xcode 껐다 켜고 빌드. 안드로이드 `strings.xml`도 같은 값으로
- [x] 시뮬레이터 테스트 끝(2026-10-30) — `test-push/README.md` 1~6. 동의 팝업·좋아요 팝업·알림 탭 5종·마이 › 알림·게스트
- [x] 실기기 + 운영 플래그 잠깐 켜기 끝(2026-10-30) — `test-push/README.md` 7. 주간 추천 실제 수신·탭(`app_opened_push{weekly_pick}`, `source: weekly`) / 「수신거부」 → 동의 false → 재발송 안 옴
- [x] 1.3.2(29) 준비 — 버전·위젯 버전·What's New 4줄(ko 포함). 기존 계정은 코치마크·시드 고르기 생략(`MainTabView`), 디버그 초기화 행 2개(신규·업데이트)

### 5. Confluence 기획 댓글 반영 (댓글 2026-11-01, 코드 대조 2026-11-04)

출처는 02. Product 「[기능] 푸시알림 컨텐츠 신규 기획」(12713985) 인라인 댓글이다. 전부 미해결 상태이고, 댓글로 제안된 0-5·0-6·0-7은 아직 본문에 없다.
서버 몫은 `dignify-backend/TODO.md` P1-b 5, 안드로이드 몫은 `dignify-android/TODO.md` 재방문 푸시 6.

**이미 맞는 것(할 일 없음):** 앱 동의 → 동의한 유저만 시스템 권한 요청 순서 / OS 권한과 무관하게 기존 유저 전원에게 첫 실행 팝업 / 동의 전 광고성 발송 차단 / 발송 시점에 동의 조회(`sendEach`·`broadcast`).

**먼저 정할 것**
- [ ] 1.3.2 범위: 아래 중 어디까지 심사 전에 넣을지. 카테고리 토글은 서버와 양쪽 앱을 다 바꾼다. 동의 팝업 요건은 제출 전에 넣길 권한다: `didOfferAdConsent`로 1회만 물어서, 지금 문구로 나가면 기존 유저에게 다시 묻기 어렵고 요건 미달이면 받은 동의가 무효일 수 있다
- [ ] 동의 기준: 계정 / 기기. 지금은 계정 기준이고, 기기 기준은 DB 수정이 필요하다(11-01 답글, 영향 범위 미검토)
- [ ] 수신거부 방식: 본문 문구 대신 알림 액션으로 갈음할 수 있는지 점검(11-01 답글). iOS 액션은 알림을 길게 눌러야 보인다. 0-7은 「알림 설정 화면 딥링크」인데 지금은 앱을 안 열고 바로 처리한다
- [ ] `(광고)` 위치: 본문 0-2는 제목 맨 앞, 댓글은 본문 맨 앞. 근거가 타사 사례뿐이라 안내서 표기 규정을 확인한 뒤 확정(변경은 서버에서)
- [ ] 알림의 「수신거부」가 끄는 범위: 전체 / 그 알림의 카테고리

**동의 팝업 요건**
- [ ] 첫 실행 팝업(`FeedView` `showAdConsent`): 「Dignify의 광고성 정보(앱 푸시) 수신에 동의하십니까?」 형식으로 전송자·광고 내용(큐레이션·신곡·주간 추천)·매체를 함께 쓰고, 버튼은 「동의」「거부」. 지금은 「새 음악 소식, 알림으로 받을까요?」 + 「알림 받기」「나중에」다. 문구는 UX Writing 확정분을 쓴다
- [ ] `PushOptInPopup`에 버튼 라벨 인자 추가. 픽·아티스트 요청 팝업의 라벨은 그대로 둔다
- [ ] 바깥 탭 처리 확인: `DSPopupHost(onDismiss: onDecline)`이라 첫 실행 팝업은 딤만 눌러도 거부로 저장되고 통지까지 뜬다. 동의 팝업은 명시적 선택만 받게 한다
- [ ] 좋아요 팝업에도 같은 요건 적용. 지금 「나중에」는 서버에 안 올리고 통지도 없다. 「거부」로 바꾸면 `PUT false` + 통지가 되고, 1-7 논의 2의 「나중에」 동작과 충돌하니 문서도 맞춘다
- [ ] 이미 동의했고 권한만 미결정이면 동의 문구 없이 권한만 묻는다. 지금은 `acceptAdPush`가 `PUT true`를 다시 보내 동의일을 덮어쓰고 통지도 또 뜬다(안드로이드는 `promptNeedsConsent`로 분기)

**0-5 상태별 규칙 — 지금 코드와 다른 칸**
- [ ] 미응답과 거부 구분: 서버 `adPushConsentAt`을 받아 쓴다(null = 미응답). 지금은 boolean + 기기의 `didOfferAdConsent`라 재설치·기기 변경 시 이미 답한 유저에게 또 뜬다
- [ ] OS 허용 + 거부, OS 거부 + 거부: 좋아요 시점 재동의 제안. `queueHypeOffer`의 `pushAuthorizationUndecided()` 조건 때문에 지금은 안 뜬다
- [ ] OS 거부 + 미응답/거부에서 동의: 설정 앱으로 바로 넘기지 말고 「설정에서 알림 켜기」 안내를 먼저 보여 준다(`acceptAdPush`)
- [ ] OS 거부 + 동의: 「설정에서 알림 켜기」 안내 추가. 띄울 시점이 댓글에 없어 확인 필요
- 세션당 1회, 「나중에」 뒤 재질문 조건은 지금 규칙을 유지한다

**처리 결과 통지**
- [ ] 팝업 → 토스트(11-01 답글로 합의): `MainTabView`의 `DSNoticePopup`을 교체. 공용 토스트가 없어 `PickListView.showToast`를 참고한다. 전송자·처리 일자·처리 내용을 넣고, 댓글 0-5·0-7에 남은 「통지 팝업」 표현도 고쳐 달라고 한다
- 알림 「수신거부」는 앱이 안 떠 있을 수 있어 로컬 알림 통지를 유지한다

**마이 › 알림** (서버 카테고리 배포 뒤)
- [ ] 전체 토글 + 카테고리 토글 3개(큐레이션·신곡·주간 추천). 야간 발송을 하기로 하면 야간 토글 추가
- [ ] OS 알림이 꺼져 있으면 상단에 「기기 알림이 꺼져 있어요 → 설정 열기」. 지금은 화면 아래 행으로만 보인다
- [ ] 수신거부 방식이 딥링크로 정해지면 알림 액션 → 이 화면 연결. 로그인 없이 끌 수 있어야 한다
- [ ] 계측 추가: 카테고리별 OFF율 이벤트. 이름은 안드로이드와 똑같이 맞춘다

**로그아웃 기기 발송 차단** (계정 기준 유지 시, 서버 계약 먼저)
- [ ] `logout()`에서 기기 토큰을 서버 계약에 맞춰 함께 처리하고, 재로그인 때 다시 등록되는지 확인. 지금은 로그아웃해도 토큰이 남아 광고성 알림이 온다

**2년 재확인**
- [ ] 안내 알림 탭 → 마이 › 알림 연결. 11-01 답글은 「앱 쪽 재안내 팝업」이지만, 댓글 근거상 로그인 때 뜨는 팝업으로는 인정되지 않아 서버 발송이 필요하다. 첫 동의 후 23개월이라 급하지 않다

**문서**
- [ ] 댓글 0-5·0-6·0-7과 수정 제안을 본문에 반영해 달라고 요청. 지금 본문과 댓글이 다른 곳이 많아 구현 기준이 갈린다

---

## 🔭 다음에 할 일은 기능이 아니라 **판독이다**

**이제 두 릴리즈치 계측이 안 읽힌 채로 쌓여 있다.** 1.1.1의 9종은 아직 한 번도 안 봤고,
1.2.0의 `background` 3종이 그 위에 얹혔다. **데이터가 쌓이기 전에 다음 기능을 얹지 말 것** —
지금 새 기능을 제안하면 두 릴리즈가 먹혔는지 영영 모른 채로 간다.

| 질문 | 볼 것 | 답이 이렇게 나오면 |
|---|---|---|
| 고정 시드 풀이 취향을 덮나 | `onboarding_seed_selected{from}`의 `search` 비율 | 높으면 **풀 재선정**(`ops/onboarding-seed-pool.sql`). 이게 이 개편의 핵심 질문이다 |
| 재생이 회상을 돕나 | `pick_track_previewed` 발생률 | 낮으면 리스트 개편의 전제가 틀린 것 |
| 작성화면 85% 이탈은 어디였나 | `pick_compose_opened` → `pick_track_selected` → `pick_title_step` → `pick_created` | 곡 선택에서 끊기는지 제목에서 끊기는지가 처음으로 갈린다 |
| 온보딩 뎁스를 줄인 게 먹혔나 | `onboarding_seed_done{count}`, 이후 세션 디깅 뎁스 | 신규 유입 하루 1~5명이라 **A/B로는 판정 못 한다.** 절대값 추세만 본다 |
| **백그라운드를 실제로 쓰나** | `track_viewed{background:true}` 발생 유저 수 | 0에 가까우면 1.2.0은 안 쓰인 기능이다. 위젯(P8) 판단의 전제이기도 하다 |
| **잠금 재생이 뎁스를 부풀리나** | 디깅 뎁스를 `background=false`로 한 번 더 | 두 값이 벌어지면 뎁스 시계열의 1.2.0 이후 구간을 그대로 못 읽는다 |

⚠️ **`background` 계측 규칙 두 개를 기억할 것.**
`track_dwell`만 발사 시점이 아니라 **백그라운드 진입 시점**에 표시된다 — 주머니에서 10분 듣고
복귀해 스와이프하면 발사는 포그라운드에서 일어나서, 그대로 읽으면 중앙값 2.0초 분포에 600초가 섞인다.
`track_listened`엔 플래그가 없다(30초 들었으면 들은 것이다).
**남은 구멍**: 자동 넘김과 잠금화면 수동 스킵이 둘 다 `background:true`라 구분이 안 된다.
"백그라운드를 쓰나"는 답하지만 "적극적으로 넘기나"는 못 가른다. **그 질문을 물을 근거가 생기기 전엔
속성을 더 붙이지 말 것.**

⚠️ **성공 기준을 "픽 게시자 수"로 잡지 말 것.** n이 8→12로 움직여도 판정이 안 된다.
**게시자의 재게시율·잔존**으로 본다(2026-08-31 확정).

**계측 정본은 `digging/09_analytics_queries.md`.** 1.1.1 신규 9종과 1.2.0의 `background` 속성이
아직 거기 안 적혔다 — 판독 전에 추가할 것.

**안드로이드 포트 지시는 써뒀다** — `../dignify-android/docs/1.2.0-port-checklist.md` + 그 리포 `TODO.md` 최상단.
**직역이 틀리는 첫 포트다**(포그라운드 서비스 필수, Live Activity는 포트 대상 아님 — 미디어 알림이 그 자리다).

---

## 📌 릴리즈 자산에 남은 구멍 (마케팅)

- **영문 App Store 스크린샷 1번이 한국어 이미지다.** en 촬영본이 없어 ko를 그대로 썼다
  (`marketing/appstore/screenshots/build.py` 주석). 영문 기기로 다시 찍어 교체할 것.
- ✅ **스토어 설명·프로모션 텍스트는 2026-09-03에 갱신했다**(한/영). 이때 **영문 설명의
  `Pick the genres you care about and the feed follows.` 불릿이 1.1.0부터 거짓말이었던 걸 발견**해
  하입 기반 피드 문구로 바꿨다(장르 선택은 코드째 삭제된 기능). 한국어에 없던 같은 줄도 넣어 6줄로 맞췄다.
  **리스팅 문안은 리포에 파일이 없다 — App Store Connect에만 있다.**
- **`05-your-crate` 슬라이드가 옛 문구다.** 화면이 `하입한 곡`으로 바뀌었는데 스크린샷 속은 `담은 곡`이다.
  촬영본이 있어야 고칠 수 있다.

---

## P1. AdServices 설치 귀인 — 다음 릴리즈

**지금 앱에 귀인 코드가 0줄이라 "이 유저가 광고로 왔는지"를 알 방법이 없다.**
2026-08-07 판독에서 PostHog 신규 13명과 Apple Ads 설치 14건을 손으로 맞춰봤는데,
날짜 창을 UTC로 맞추고 노이즈를 거르는 데만 세션 하나가 들었다. 그러고도
같은 날 터진 유입 스파이크(2시간 반에 9명)가 광고인지 아닌지 확정하지 못했다.

`AdServices` 프레임워크(iOS 14.3+)가 `campaignId` / `adGroupId` / `keywordId`를 준다.
ATT 프롬프트 불필요(애플 1st-party).

```swift
import AdServices

// ponytail: 최초 1회만, 실패하면 조용히 포기 — 귀인 없으면 오가닉으로 읽으면 된다
func captureAdAttribution() {
    guard !UserDefaults.standard.bool(forKey: "adAttributionSent") else { return }
    Task {
        guard let token = try? AAAttribution.attributionToken() else { return }
        var req = URLRequest(url: URL(string: "https://api-adservices.apple.com/api/v1/")!)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(token.utf8)
        // 설치 직후엔 404가 뜨는 창이 있어 재시도가 필요하다
        for delay in [0, 5, 10] {
            try? await Task.sleep(for: .seconds(delay))
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            PostHogSDK.shared.capture("install_attributed", properties: json)
            PostHogSDK.shared.register(json)   // 이후 모든 이벤트에 자동으로 붙는다
            UserDefaults.standard.set(true, forKey: "adAttributionSent")
            return
        }
    }
}
```

`register`가 핵심이다 — 이후 모든 이벤트에 `keywordId`가 붙어서 코호트 분석이 그냥 된다.

**왜 CPA보다 중요한가.** 지금 광고는 CPA(설치 단가)로만 최적화하는데 실제 목표 지표는
디깅 뎁스다. 둘은 어긋날 수 있다. `keywordId`가 붙으면 "`음악` EXACT 유저는 중앙값 30곡,
`음악 추천` 유저는 3곡" 같은 게 바로 나온다. **CPA로는 절대 못 보는 값이다.**
2026-08-07에 `음악 추천` 입찰을 CPA $3.96만 보고 내렸는데, 그쪽 유저가 더 깊게 판다면
틀린 결정이었을 수 있다.

**한계 (기대치 조정용)**
- Apple Search Ads만 판별한다. 인스타·커뮤니티는 전부 `attribution: false`로 뭉친다.
- 앞으로의 설치만. 과거 소급 안 됨.
- **App Privacy 라벨 재확인 필요.** (1.0.8·1.1.0 모두 배포 완료 — "심사 중이라 대기"는 해소됐다.)

---

## P2. `listenThreshold` 재검토 — 1.0.8 dwell 데이터 쌓인 뒤

`Core/Audio/FeedAudioController.swift:43` — `listenThreshold = 5`로 하드코딩.
같은 파일 22번 줄에 문제가 이미 주석으로 적혀 있다: **임계값이 실측 체류 분포
한가운데(4~12초)에 앉아 있어 스와이프 속도만 변해도 청취율이 절반씩 꺾인다.**
그래서 2026-08-05에 주지표를 청취율에서 디깅 뎁스로 교체했다.

1.0.8에 `track_dwell` 계측이 들어갔다(`Features/Feed/FeedView.swift:1017`).
1.1.0까지 배포됐으니 데이터는 쌓여 있다 — `09_analytics_queries.md`의 **A-9**로 분포를 보고 판단한다.

- **3초대에 몰리면** → `listenThreshold` 하향이 정답
- 분포가 넓게 퍼지면 → 임계값을 만지지 말고 진행바 같은 UI 쪽으로

**데이터 없이 먼저 건드리지 말 것.** 지금 바꾸면 기존 청취율 시계열이 끊긴다.

⚠️ **2026-09-03 추가 — 이제 A-9를 `where background = false`로 걸어야 한다.**
1.2.0부터 주머니 속 재생이 같은 이벤트로 들어온다. 백그라운드 체류는 "폰을 안 만진 시간"이라
분포에 섞이면 임계값 판단이 그대로 깨진다. 이 항목이 `background` 속성을 만든 직접적인 이유다.

---

## P3. 게스트가 신고/차단에 접근 못 함 — 심사 리스크

`Features/Picks/PickListView.swift:225`, `:402` — 픽의 `···` 메뉴가 `requireAccount()`
가드 뒤에 있어서 **게스트는 메뉴 자체가 안 열리고 로그인 시트로 튄다.**

1.0.8이 이 앱의 첫 UGC 릴리즈였고 **Guideline 1.2가 계속 적용**되는데,
기존 심사 메모가 "계정 없이 이용 가능"을 강조한다. **리뷰어가 게스트로 테스트하면
"조정 수단이 없다"로 읽힐 수 있다.** 1.0.8 심사 메모에는 로그인 후 테스트하라는
경고를 넣어 우회했다(`marketing/appstore/review-notes.md`).

**우회가 아니라 고치려면** 신고만 게스트에게 열어주면 된다(차단은 계정이 필요하니 그대로).
UGC를 걷어내지 않는 한 매 릴리즈 재확인 대상이므로, 언젠가는 고치는 쪽이 싸다.

---

## P4. 캐릭터 프로필 — 하입 순환 + 수익화 (기획 확정, 코드 0)

2026-08-07 결정. **하입이 지금 유저에게 돌려주는 게 없다** — 크레이트에 쌓이기만 하고
눈에 보이는 변화가 없다. 누적 하입으로 프로필 캐릭터를 키우고, 추가 캐릭터는 결제로
해금한다. 1.0.8에 픽이 나가면서 **남의 프로필을 볼 이유가 처음 생긴 것**이 전제다.

### 확정된 것

- **결제는 non-consumable 해금 하나만.** 재화 충전(consumable)·구독 전부 기각 —
  전자는 서버 원장·중복지급·환불 처리가 붙고, 후자는 갱신/이탈/유예기간 상태관리가 남는다.
  non-consumable은 복원이 `Transaction.currentEntitlements` 한 줄이다.
- **재화 테이블 없음.** `API.UserStats.hypeCount`(`Core/Network/DTOs.swift:136`)가
  이미 누적 하입을 내려준다. 무료 해금은 "누적 하입 N개" 파생값으로 판정하면
  잔액·지급·중복방지가 전부 사라진다. 일일 적립보다 하입 스팸 유인도 약하다.
- **소유 상태도 서버가 안 든다.** 유료 캐릭터의 원본은 StoreKit이고, 서버는
  **착용 중인 id 한 컬럼**만 있으면 된다 — 남에게 보여줘야 하는 건 그것뿐이다.
- **무료/유료 카탈로그를 분리한다.** 같은 캐릭터에 하입 가격과 원화 가격을 둘 다 붙이면
  밸런싱이 영구히 따라온다. 무료는 하입 임계 전용, 유료는 결제 전용으로 겹치지 않게.
- **해금 조건은 총량이 아니라 취향 데이터에 건다.** 음악 앱에 캐릭터가 있을 이유가
  약한 게 이 기획의 유일한 구멍인데, `hypedByGenre` / `hypedByArtist` / 취향 유형 4개가
  이미 서버에 있다. "그 장르 하입 N개 → 그 장르 아이템" 이면 꾸미기가 곧 취향 표시가 되고
  추가 데이터도 필요 없다.

### 순서 — 1단계 지표 없이 2단계로 가지 말 것

**1단계. 볼 자리 만들기 (재화·결제 0줄)**

지금 픽에서 작성자로 갈 수가 없다. `API.Pick`에 닉네임은 있는데 **`userId`가 없고**
(`Core/Network/DTOs.swift:160`), 프로필은 `mine=true` 자기 것 전용이다.

```
users.equipped_character  varchar   -- 착용값만
PickResponse.userId       추가
GET  /users/{id}          공개 프로필(nickname, equippedCharacter, hypeCount, picks)
PUT  /users/me/character  착용 변경
```

iOS는 픽 작성자 탭 → 공개 프로필. 캐릭터는 **무료 기본 세트만**, 결제 없음.
여기서 `profile_opened`만 보면 답이 나온다 — **남의 프로필을 안 열면 코스튬은 안 팔린다.**
이게 아트 에셋을 쏟아붓기 전에 가능한 유일하게 싼 검증이다.

**2단계. 하입 임계 해금 + StoreKit 결제.** 1단계 지표가 나온 뒤.

### 걸리는 것

- **픽 카드는 2026-08-04에 아바타를 일부러 뺐다.** 350pt 세로 카드에 자리가 없어서였다.
  캐릭터를 카드에 다시 넣으려면 그때 뺀 이유를 다시 풀어야 한다. 프로필에만 크게 넣고
  카드는 손대지 않는 선택지가 있다.
- **소유 검증 구멍.** 서버가 검증을 안 하므로 API로 안 산 캐릭터를 착용할 수 있다.
  지금 규모에선 무시하고, 실제로 나오면 영수증 검증을 붙인다.
- **진짜 비용은 코드가 아니라 아트 에셋이고, 한 번이 아니라 계속이다.**
  1단계를 먼저 두는 이유가 이것이다.
- IAP가 처음 들어가므로 App Privacy 라벨·계정삭제 흐름 재확인이 따라온다.

---

## P5. Pick 활성화 — 진단 (다음 판독의 기준선)

작업 3개(재생 수·작성화면 개편·`Your hypes` 개명)는 1.1.1로 나갔다 — 맨 아래 이력.

**8/29에 "픽 단독 개선 항목은 접는다"고 쓴 근거가 절반 틀렸다.** 아래 정정을 먼저 읽을 것.

### 퍼널 실측 (8/7~8/31, 계측 시작 이후, 노이즈 제외 iOS 314명)

| 단계 | 유저 | 전환 |
|---|---|---|
| Picks 탭 도달 (`pick_list_viewed`) | 237 | 전체의 75% |
| **New pick 클릭** (`pick_compose_opened`) | **53** | **탭 대비 22.4%** |
| 게시 (`pick_created`) | **8** | **클릭 대비 15.1%** · 탭 대비 3.4% |
| 남의 픽 열어봄 (`pick_opened`) | 126 | 탭 대비 53% |

**🔑 클릭률은 낮지 않다.** 90-9-1(Nielsen)에서 창작자는 모수의 1%인데 게시자가 **2.5%**,
작성화면 진입이 **17%**다. **전환율이 아니라 모수가 문제다.**
→ **이 트랙의 성공 기준을 "게시자 수"로 잡지 말 것.** n이 8→12로 움직여도 판정이 안 된다
(1.1.0에서 이미 겪은 그 문제다). **게시자의 재게시율·잔존**으로 잡는다.

**진짜 절벽은 클릭 다음이다** — 연 53명 중 45명(85%)이 아무것도 못 내고 나갔고,
**32명은 딱 한 번 열어보고 재시도가 없다**(게시자는 클릭 중앙 2회).

### ⚠️ 진단 정정 — "하입 6곡 문턱"은 **클릭 단계에선 사용량 대리변수였다**

8/29 수치(0~5곡 26명 생성 0 / 6곡+ 29명 중 11명)는 **노출을 통제하지 않았다.**
탭 도달 237명 전수로 다시 재고 층화하면 클릭 단계의 하입 효과는 **사라진다**:

- 노출 50~199 안에서 하입6+ 28.1% vs 하입<6 27.8% (**p=1.000**)
- 노출 200+ 안에서 61.1% vs 66.7% (**p=1.000**)
- 클릭을 실제로 가르는 건 **사용량**: 노출 0-9 **3.6%** / 10-49 13.7% / 50-199 28.0% / 200+ **61.9%**,
  픽탭 방문 1회 **2.7%** / 2-3회 18.4% / 4회+ **45.5%**

**게시 단계에선 하입 효과가 남는다**: 6곡+ 8/85 vs 6곡 미만 **0/152** (p=0.00022),
노출 50~199로 층화해도 6/57 vs 0/36 (p=0.078).

→ **"절벽은 UI가 아니라 재료"는 게시에만 맞고 클릭에는 틀리다. 두 단계의 병목이 다르다.**

### 🔴 계측 공백 — 남은 2개

1. ~~작성화면 내부 무계측~~ — **1.1.1에서 닫힘**(이벤트 4종, 이력 참조).
2. **게스트 클릭은 아예 안 찍힌다.** `PickListView.swift:306` 버튼 → `requireAccount()`(`:530`)가
   `.guest`면 시트를 안 열고, 이벤트는 시트의 `.task`에서 찍힌다. **22.4%는 하한이다.**
3. `pick_list_viewed`는 `.task` = **앱 실행당 1회**라 "픽탭 방문 횟수"는 사실상 앱 실행 횟수다.
   또 목록이 비면 `New pick`이 숨고 emptyView의 "Make a pick"으로 대체되는데
   **두 경로가 같은 이벤트로 수렴**해 구분이 안 된다.

### 확정된 순서 (2026-08-31 사용자)

**① 매일 시딩 루틴(`../dignify-backend/TODO.md` P1-a, 운영 중) → ② 리턴 가시화(1.1.1 완료) → ③ 작성화면 개편(1.1.1 완료).**
**소셜 리턴(Blend형 취향 일치율)은 기각** — 유저 모수가 적어 의미 없다는 판단.
**광고·금전 보상도 보류** — 과잉정당화 효과(이미 보상 없이 올리는 8명의 동기를 재정의한다)와
Medium Partner Program 전례(스팸·AI 글 폭증), 그리고 DAU 10명 규모에서 산수가 안 맞는다.

---

⚠️ **남은 crate 문구 1건** — 로그인 유도문 `Sign in to hype tracks, … build your crate.`(ko `담은 곡`).
1.1.1 개명 범위 밖이라 안 건드렸다. 같이 옮길지는 판단 필요. `WhatsNewView`의 과거 릴리즈 노트는 건드리지 말 것.

⚠️ **폐기된 진단 (다시 제안하지 말 것)**
- ~~"작성 플로우가 빈 그리드에서 시작한다"~~ → **거짓.** `PickComposeView.loadCrate()`가
  `.myHypes()`를 부른다(`:448`). **크레이트 = 하입 목록**이라 소스 연동은 이미 돼 있다.
- ~~시드 플래그(`is_official`) 전환 선행~~ → **보류 유지. 원인은 2026-08-31에 확정됐다** —
  시딩 SQL이 일부러 FALSE로 넣고, 그건 `ORDER BY isOfficial ASC`가 TRUE를 목록 맨 뒤로
  밀기 때문이다. 정렬 축과 계측 축이 같은 컬럼이라 둘 다 못 얻는다.
  **고치지 말고**, 시딩 효과는 `picks.play_count`로 DB에서 잰다.
  상세는 `../dignify-backend/TODO.md` P1-a.
- ~~"픽 단독 개선 항목은 접는다"~~ → **위 정정 참조.** 접을 근거였던 하입 문턱이 클릭 단계에선
  사용량 교락이었다.


---

## P6. 픽 반응 푸시 → 픽 상세로 — 서버 `pickId` 대기

1.1.1부터 `pick_reaction` 푸시를 누르면 **내 픽 목록(디깅 프로필)까지** 간다. 그 픽 상세로 바로 보내려면
서버가 `pickId`를 실어야 한다(`../dignify-backend/TODO.md` P2-b). 붙으면 클라는 `AppDelegate` 분기 한 줄이다.
반응이 달린 픽을 바로 여는 게 알림이 약속한 것이고, 도달과 함께 `play_count`도 오른다.
⚠️ 그때 `PushService.pickReactionAlert`의 "유도 문구 안 넣음" 전제가 풀리니 문구도 같이 손볼 것.

| type | 앱 동작 |
|---|---|
| `curation` | 피드 탭 + 세트를 앞으로 |
| `pick_reaction` | 마이페이지 → 디깅 프로필(내 픽) |
| `notice` | 앱만 열림(의도) |

---

## P8. 홈 화면 위젯 — **보류로 내린다** (2026-09-03 판단, 근거 있음)

**2026-08-31에 "P7 다음"으로 걸어뒀는데, P7을 하면서 근거가 뒤집혔다.**
익스텐션 타깃은 이미 있으니 "기왕 한 김에"가 성립할 것 같지만 **성립하지 않는다.**

**세 가지 이유로 지금이 아니다.**

1. **WidgetKit은 소리를 못 낸다.** 정적 스냅샷 + App Intent 버튼이 전부다. 음악 발견 앱에서
   소리를 뺀 위젯은 앨범아트 액자거나 딥링크 런처인데, **딥링크 런처는 홈 아이콘 대비 추가 가치가 없다.**
2. **Live Activity와 데이터 경로가 완전히 다르다.** Live Activity는 앱 프로세스가 살아 있는 동안
   앱이 직접 `update`로 민다. 위젯은 앱이 죽은 상태에서 혼자 그려야 하는데 **이 앱엔 App Group이
   하나도 없고** 하입 목록은 `myHypes` 서버 API에만 있다. 위젯이 볼 로컬 데이터가 0이라
   App Group 컨테이너 + 캐시 쓰기 + 타임라인 프로바이더가 전부 신규다. 타깃 생성은 전체의 5%다.
3. **판정이 불가능하다.** 위젯 설치율은 보통 앱 설치 유저의 5% 미만이고 신규 유입이 하루 1~5명이다.
   만들어도 먹혔는지 알 방법이 없다 — 이 파일 맨 위의 원칙에 정면으로 걸린다.

⚠️ **"현재 커서 기준 트랙"은 후보가 아니다**(2026-09-03에 검토하고 뺐다).
앱을 안 열면 커서가 안 움직여서 **며칠째 같은 곡이 박혀 있는 죽은 위젯이 된다.**
게다가 커서 트랙은 **이미 본 곡**이라 재방문 동기가 0이다. 위젯의 목적과 정반대로 작동한다.
(기존 주석대로 "새로 들어온 트랙"도 후보가 아니다 — 카탈로그는 매일 늘지 않는다.)

**되살릴 조건**: 위 판독표의 `track_viewed{background:true}`가 "백그라운드를 실제로 쓴다"고
답한 뒤. 그때는 익스텐션 타깃이 이미 있어 App Group만 추가하면 된다.
그 시점에 가장 덜 나쁜 후보는 **마지막 하입한 곡 액자 + 피드 딥링크**다 — 하입할 때 앱이 곡명과
아트워크 URL만 App Group에 써두면 위젯 쪽 네트워크도 토큰도 필요 없다.

---

## P9. 하입 내보내기 — Apple Music (MusicKit) (**작업 대상**, 2026-08-31 추가)

**1.1.1 범위 아님.**

**하입이 지금 앱 안에 갇혀 있다.** 밖에서 가치를 가지면 하입할 이유가 커지고,
그건 **픽 게시 문턱(하입 6곡, p=0.00022)과 같은 방향**이다. 리텐션 항목이면서 동시에 픽 활성화 항목이다.

- Apple Music 플레이리스트로 내보내기. **클라이언트 MusicKit만으로 되고 서버 작업이 없다.**
- 매칭은 곡명·아티스트명 문자열이라 **실패가 난다.** 실패분을 어떻게 보여줄지가 UX의 본체다.
- ⚠️ **유튜브 뮤직 내보내기는 추후 검토**(사용자 지시). OAuth + 별도 API라 서버가 붙고
  비용이 Apple Music과 자릿수가 다르다. **Apple Music 먼저 내고 수요를 보고 판단한다.**

---

## 이력 (완료)

| 릴리즈 / 항목 | 날짜 | 요약 |
|---|---|---|
| **1.2.0** (빌드 23) = P7 | 2026-09-03 | 화면을 꺼도 디깅이 이어진다: 백그라운드 재생, 잠금화면·이어폰 다음/이전, 백그라운드에선 30초 후 다음 곡, Live Activity 하입(`dignifyWidget`). 계측에 `background` 속성. 함정 7종은 Claude 메모리 `project_background_audio_traps` |
| **1.2.1** (빌드 24) | 출시 | 이번 주 특집 배지가 모드 칩과 겹치던 버그 |
| **1.1.1** (빌드 22) | 2026-09-02 | P0 온보딩을 인기곡 풀에서 직접 고르기로(`SeedPoolPickerView`, 2지선다 삭제) · P5 작업 1~3(픽 카드 재생 수 5 미만 숨김 / 작성화면 날짜별 리스트+재생, 셀 `PickTrackRow` / `Your crate`→`Your hypes`) · P6 반응 푸시 → 내 픽 딥링크. 백엔드 선행 3건 같은 날 배포 |

### P7에서 닫은 판단 (다시 열지 말 것)

1. **iTunes 프리뷰 약관** — 막지 않는다(2.5.4). 백그라운드 무한 루프가 오히려 불리해서 자동 다음 곡으로 갔다.
2. **자동 진행 규칙** — 피드 순서 그대로 다음 곡. 백그라운드에서만, 분기는 `FeedAudioController.handleTrackEnd(id:)` 하나.
3. **계측 오염** — `source`와 직교하는 별도 `background` 속성. 판독 쿼리는 `where background = false`.
4. **잠금화면 스크러버 드래그는 안 넣었다** — `changePlaybackPositionCommand`·`skipForward`·`seek` 전부 끔.
   열면 "재생 위치 = 실제 들은 시간" 등식이 깨져 `listened_tracks`·`track_dwell`이 무너진다.
   열려면 시크 발생 트랙의 청취·체류 처리 규칙부터 정할 것.
5. **심사 메모** — `Background audio is used to continue music playback while the screen is locked.`
   (`marketing/appstore/review-notes.md`)

### 1.1.1에서 배운 것

- `PickTrack`의 `==`는 **trackId만** 본다. 검색 결과엔 `hypedAt`이 없어 전 필드 비교면 같은 곡이 두 번 담긴다.
- 작성화면 계측 4종: `pick_track_selected{from, selected_count}` · `pick_title_step{track_count}` ·
  `pick_submit_failed{reason, track_count}` · `pick_track_previewed{from}`.
- 하입 지점부터 재생은 안 넣었다 — `HypeItem`에 위치 필드가 없다.
