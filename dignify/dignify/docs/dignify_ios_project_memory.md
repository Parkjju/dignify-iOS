# Dignify iOS Project Memory

작성일: 2026-06-30  
목적: Dignify iOS 앱 개발을 시작하기 위한 스펙, 우선순위, 일정, 구현 기준을 하나의 기준 문서로 고정한다.

---

## 1. 제품 정의

Dignify는 30초 음악 프리뷰를 릴스처럼 빠르게 넘기며 새로운 트랙을 발견하는 iOS 앱이다.

핵심 인사이트:

> 좋은 음악은 10~20초면 판단 가능하다.

핵심 경험:

1. 앱 진입
2. 30초 프리뷰 자동 재생
3. 위/아래 스와이프로 트랙 탐색
4. 더블탭으로 하입
5. 상세 보기 또는 Apple Music으로 이동

MVP의 성공 기준은 완성된 커뮤니티가 아니라, “음악을 빠르게 발견하고 하입하는 루프”가 자연스럽게 작동하는 것이다.

---

## 2. MVP 범위

### 포함

- Apple Sign In
- JWT 기반 로그인 상태 유지
- 온보딩 장르 선택 0~3개
- 피드 자동 재생
- 피드 스와이프 탐색
- 더블탭 하입 토글
- 검색
- 트랙 상세 하프 모달
- Apple Music 외부 링크
- 마이페이지
- 내가 하입한 트랙 목록
- 닉네임 변경
- 장르 재설정
- 로그아웃
- 계정 삭제
- 이용약관 / 개인정보처리방침 인앱 화면
- 첫 재생 15초 이상 청취 시 listen 이벤트 전송

### 제외

- 유저 포스팅
- 댓글
- 신고 기능
- 리더보드
- 얼리 디거 뱃지
- 푸시 알림
- 구독 결제
- Deezer / Spotify 동시 지원
- 복잡한 개인화 추천

---

## 3. iOS 개발 기준

### 플랫폼

- iOS 17+
- SwiftUI
- MVVM 기반, 단 과도한 ViewModel 남발 금지
- Swift Concurrency async/await 사용
- 라이트 모드 단독
- iPad 대응 없음

### 아키텍처 결정

TCA(The Composable Architecture)는 MVP 단계에서 도입하지 않는다.

도입하지 않는 이유:

- 2026-07-15 마감 일정에는 reducer / action / effect 설계 비용이 크다
- 현재 앱의 전역 상태는 인증 상태, 피드 상태, 플레이어 상태 정도로 제한적이다
- Dignify의 핵심 복잡도는 상태 관리 프레임워크보다 AVPlayer, 스와이프 전환, 버퍼링, 앱 lifecycle 처리에 있다
- Figma 기반 UI를 빠르게 구현하고 검증해야 하므로, 얇은 SwiftUI-native 구조가 더 유리하다
- 외부 라이브러리 의존도를 줄이면 빌드/디버깅/온보딩 속도가 빨라진다

대신 사용할 구조:

- SwiftUI
- Observation (`@Observable`)
- async/await
- 명시적인 Service 계층
- 필요한 곳에만 가벼운 feature model 사용

권장 예시:

```swift
@Observable
final class AppSession {
    var authState: AuthState = .unknown
}

@Observable
final class FeedModel {
    var items: [FeedItem] = []
    var currentIndex: Int = 0
    var isLoading = false
}
```

서비스 계층:

```text
AuthService
FeedService
PlaybackController
TokenStore
APIClient
```

나중에 TCA를 다시 검토할 조건:

- 피드 / 플레이어 / 캐시 / 딥링크 / 결제 / 오프라인 상태가 서로 강하게 얽히기 시작할 때
- 테스트 가능한 복잡한 상태 전이가 MVP 이후 핵심 문제가 될 때
- 팀원이 늘어나고 feature module 간 규칙 강제가 필요할 때

### 상태 관리

- 화면 내부 상태: `@State`
- 루트 소유 앱 상태: `@State` + `@Observable`
- 앱 공통 서비스: `@Environment`
- Feature-local dependency는 initializer injection 우선

### 앱 구조

초기 구조:

```text
DignifyApp
└─ AppRootView
   ├─ OnboardingFlowView
   └─ MainTabView
      ├─ FeedView
      └─ MyPageView
```

권장 디렉토리:

```text
dignify/
├─ App/
├─ Core/
│  ├─ Auth/
│  ├─ Networking/
│  ├─ Models/
│  ├─ Playback/
│  ├─ Routing/
│  └─ DesignSystem/
├─ Features/
│  ├─ Onboarding/
│  ├─ Feed/
│  ├─ TrackDetail/
│  ├─ Search/
│  └─ MyPage/
└─ Resources/
   ├─ Localizable.xcstrings
   └─ Assets.xcassets
```

---

## 4. 디자인 시스템 기준

Figma Make에서 정리된 디자인 시스템과 export zip 코드를 SwiftUI에 먼저 옮긴다.

참고 소스:

- Figma Make URL: `https://www.figma.com/make/o5p5qGeUI5SgToLxpW59cF/iOS-%EC%95%B1-%EB%94%94%EC%9E%90%EC%9D%B8-%EC%9A%94%EA%B5%AC%EC%82%AC%ED%95%AD`
- Export zip: `/Users/parkjju/Downloads/iOS 앱 디자인 요구사항.zip`

Export zip은 React / TypeScript / Tailwind 기반이므로 iOS에 직접 붙이지 않는다. 대신 아래 요소를 SwiftUI로 번역한다.

- `src/styles/theme.css`: 컬러 토큰, radius, 기본 typography
- `src/app/components/DesignSystem.tsx`: 버튼, 칩, 서치바, 하단 네비, motion 스펙
- `src/app/components/OnboardingScreen.tsx`: 온보딩 레이아웃
- `src/app/components/GenreSelectionScreen.tsx`: 장르 선택 칩 UX
- `src/app/components/FeedScreen.tsx`: 피드 레이아웃, 검색바, 하입 인터랙션, 하단 네비
- `src/app/components/HypeIcon.tsx`: 하입 커스텀 SVG
- `src/app/components/MyPageScreen.tsx`: 마이페이지 레이아웃
- `src/app/components/TrackDetailModal.tsx`: 트랙 상세 하프 모달
- `src/app/data/mockData.ts`: mock 트랙 / 장르 데이터

### 우선 구현 토큰

1. Color
2. Typography
3. Radius
4. Spacing
5. Shadow
6. Motion

### 주요 디자인 요소

- 브랜드 무드: 조용한 프리미엄, Apple Music에 가까운 톤
- TikTok처럼 과하게 자극적인 UI는 피한다
- 라이트 모드 전용
- Deep Indigo 계열을 브랜드 포인트로 사용
- 하입 아이콘은 커스텀 SVG 가능성 있음
- 일반 아이콘은 SF Symbols 또는 Lucide 계열 참고

### 확인된 디자인 토큰

- Brand: `#4B3FD8`
- Brand Light: `#EEF0FF`
- Background: `#FFFFFF`
- Text Primary: `#111827`
- Text Secondary: `#6B7280`
- Text Tertiary: `#9CA3AF`
- Destructive: `#EF4444`
- Radius: full, 16px, 24px, 28px
- Typography:
  - Display: 2.5rem / 700
  - Title 1: 1.5rem / 700
  - Title 2: 1.1rem / 700
  - Body: 0.9375rem / 400
  - Caption: 0.75rem / 400
  - Micro: 0.65rem / 400

### 확인된 motion 스펙

- 피드 스와이프: spring, damping 30, stiffness 300
- 하입 팝: scale `[0 → 1.3 → 1 → 0]`, 0.65s
- 화면 전환: easeOut, 0.3s
- 칩 선택: color transition, 150ms
- 시트 진입: spring, damping 30, stiffness 300

### 우선 구현 컴포넌트

1. Primary Button
2. Apple Sign In Button
3. Outline Button
4. Destructive Button
5. Genre Chip
6. Search Bar
7. Bottom Tab Bar
8. Half Sheet
9. Toast / Banner
10. Skeleton Loader

---

## 5. 백엔드 API 계약

### Base URL 확인 필요

OpenAPI는 `/v1` prefix를 포함하지만, 현재 Spring Boot 코드에서는 context path 설정이 확인되지 않았다.

확정 전 iOS에서는 base URL을 설정값으로 분리한다.

```swift
enum APIEnvironment {
    static let baseURL = URL(string: "http://localhost:8080")!
}
```

나중에 `/v1` 필요 여부에 따라 한 곳에서만 변경한다.

### 인증

공개 API:

- `POST /auth/apple`
- `POST /auth/refresh`

인증 필요 API:

- `GET /genres`
- `GET /feed`
- `GET /feed/search`
- `GET /tracks/{trackId}`
- `POST /tracks/{trackId}/hype`
- `DELETE /tracks/{trackId}/hype`
- `POST /tracks/{trackId}/listen`
- `GET /users/me`
- `PATCH /users/me/nickname`
- `PUT /users/me/genres`
- `POST /users/me/onboarding/complete`
- `GET /users/me/hypes`
- `POST /auth/logout`
- `POST /auth/withdraw`

### 실제 코드 기준 주의사항

- 하입 경로는 `/hypes`가 아니라 `/hype`
- 청취 기록 경로는 `/users/me/listens`가 아니라 `/tracks/{trackId}/listen`
- 온보딩 완료 API는 실제 컨트롤러 기준 `204 No Content`
- `TrackDetail.releaseDate`는 OpenAPI상 date지만 실제 DTO는 `Instant`
- 현재 FeedItem에는 `source`, `externalUrl` 없음

---

## 6. iOS 모델 우선순위

1차 모델:

- `AuthTokenResponse`
- `ErrorResponse`
- `Genre`
- `GenreListResponse`
- `FeedItem`
- `FeedResponse`
- `UserProfile`

2차 모델:

- `TrackDetail`
- `TrackHypeUser`
- `HypeItem`
- `HypeListResponse`

요청 모델:

- `AppleSignInRequest`
- `RefreshTokenRequest`
- `NicknameUpdateRequest`
- `PreferredGenresUpdateRequest`

---

## 7. 개발 순서

### Phase 1 — 프로젝트 골격

목표: 앱이 “기본 구조”를 갖추고, 시뮬레이터에서 빈 화면이 아닌 실제 앱 shell이 보이게 한다.

작업:

- `AppRootView` 생성
- 로그인 상태 enum 정의
- `MainTabView` 생성
- `FeedView`, `MyPageView` placeholder 생성
- DesignSystem 기본 토큰 생성
- 빌드 및 시뮬레이터 확인

완료 기준:

- 앱 실행 시 루트 분기 구조가 존재
- 탭 2개가 보임
- 시뮬레이터 빌드 성공

### Phase 2 — 네트워크 / 인증 기반

목표: 실제 백엔드 API를 붙일 수 있는 기반을 만든다.

작업:

- `APIClient`
- `Endpoint`
- `HTTPMethod`
- `APIError`
- `TokenStore`
- Keychain 저장소
- access token 자동 첨부
- refresh token rotation 처리 구조

완료 기준:

- Mock 또는 localhost API 호출 가능
- 토큰 저장 / 읽기 / 삭제 가능
- 401 발생 시 refresh 시도 구조 존재

### Phase 3 — 온보딩

목표: Apple 로그인 이후 장르 선택과 온보딩 완료까지 이어지는 흐름을 만든다.

작업:

- Apple Sign In UI
- Apple identityToken 획득
- `/auth/apple` 연동
- `/genres` 조회
- 장르 선택 0~3개
- `/users/me/genres`
- `/users/me/onboarding/complete`
- `/users/me` 기반 재진입 분기

완료 기준:

- 로그인 성공 후 토큰 저장
- 온보딩 미완료면 장르 선택으로 이동
- 온보딩 완료 후 피드 탭으로 진입

### Phase 4 — 피드 UI / Mock 재생

목표: 실제 플레이어 전, 피드 UX를 먼저 고정한다.

작업:

- Feed mock fixture
- 아트워크 중심 피드 화면
- 위/아래 스와이프 전환
- 싱글탭 pause 상태 UI
- 더블탭 하입 애니메이션
- 하단 버튼 영역
- Apple Music 버튼 / 더보기 시트

완료 기준:

- mock 데이터로 피드 탐색 가능
- 디자인 방향이 Figma와 크게 어긋나지 않음

### Phase 5 — AVPlayer Sliding Window

목표: 현재-이전-다음 3개 플레이어 윈도우를 안정적으로 관리한다.

작업:

- `PlaybackController`
- current / previous / next player 관리
- track 변경 시 window 재구성
- 30초 종료 후 loop
- fade in / fade out
- interruption 대응
- background 진입 시 pause
- foreground 복귀 시 자동 재개 없음

완료 기준:

- 연속 스와이프 시 재생이 무너지지 않음
- 앱 백그라운드 전환 시 재생 중지

### Phase 6 — 실제 피드 API

목표: mock 피드를 백엔드 피드로 교체한다.

작업:

- `GET /feed`
- cursor 저장
- prefetch
- hasMore 처리
- `POST /tracks/{trackId}/listen`
- 하입 여부 반영

완료 기준:

- 실제 API 데이터가 피드에 표시
- cursor 기반 추가 로딩 가능

### Phase 7 — 하입 / 검색 / 상세

목표: 피드의 핵심 상호작용을 완성한다.

작업:

- 하입 optimistic update
- `POST /tracks/{trackId}/hype`
- `DELETE /tracks/{trackId}/hype`
- 검색창
- 300ms debounce
- `/feed/search`
- 트랙 상세 하프 모달
- `/tracks/{trackId}`

완료 기준:

- 검색 결과도 피드 형태로 탐색 가능
- 트랙 상세 표시 가능
- 하입 토글 UX가 자연스러움

### Phase 8 — 마이페이지

목표: 유저 설정과 하입 히스토리를 구현한다.

작업:

- `/users/me`
- `/users/me/hypes`
- 날짜별 그룹핑
- 하입 아트워크 가로 스크롤
- 인라인 preview 재생
- 닉네임 변경
- 장르 재설정
- 로그아웃
- 계정 삭제
- 약관 / 개인정보처리방침 화면

완료 기준:

- 마이페이지 MVP 기능 전부 접근 가능
- 로그아웃 / 계정 삭제 후 인증 상태 초기화

### Phase 9 — 안정화 / TestFlight

목표: 실기기 테스트와 심사 준비를 한다.

작업:

- 네트워크 없음 처리
- 재생 오류 처리
- skeleton / empty / error state
- localization ko/en
- iTunes attribution 문구
- Apple Music 링크 항상 노출
- TestFlight 빌드

완료 기준:

- 내부 TestFlight 배포 가능

---

## 8. 일정 계획

가정:

- 1인 개발
- 백엔드 기본 API는 동작한다고 가정
- 디자인은 Figma Make 기준으로 확정
- 목표는 2026-07-15까지 MVP 개발을 마무리하고 TestFlight 후보 빌드를 만드는 것
- 7/15 마감을 위해 기능 범위는 “핵심 피드 루프” 중심으로 압축
- 완성도보다 실제 사용 가능한 end-to-end 흐름을 우선

### 7/15 마감용 범위 조정

7/15까지 반드시 포함:

- 앱 골격
- 디자인 시스템 seed
- API 모델 / 네트워크 레이어
- 토큰 저장 구조
- Apple 로그인 연동 또는 로그인 mock fallback
- 온보딩 장르 선택
- 피드 목록 조회
- 피드 UI
- 기본 AVPlayer 재생
- 하입 토글
- 검색
- 트랙 상세
- 마이페이지 기본 정보
- 로그아웃
- 최소 에러 / 로딩 / 빈 상태

7/15 이후로 미룰 수 있음:

- 완성형 AVPlayer sliding window 최적화
- fade in / fade out 정교화
- 마이페이지 인라인 재생
- 하입 히스토리 날짜별 고급 레이아웃
- 계정 삭제
- 약관 / 개인정보처리방침 최종 문구 polish
- 세밀한 localization
- 모든 motion polish
- previewUrl 검증/재시도 고도화

> **2026-06-30 재산정**: Day 1에 골격 + 디자인 시스템 + 온보딩/피드 mock UI까지 동시에 진행되어 원본 일정보다 UI 쪽이 앞서고, 반대로 네트워크/인증(Phase 2)은 미착수 상태로 뒤처짐. 아래 일정은 실제 진행 상태 기준으로 재정렬한 버전이며, 원본 Day 1~Day 16 표를 대체한다.

| 기간 | Phase | 목표 | 산출물 |
|---|---|---|---|
| 2026-06-30 | Day 1 (완료) | 앱 골격 + 디자인시스템 + 피드 mock UI | App shell, DesignSystem seed, Onboarding UI 골격, Feed mock UI (커밋 정리 필요) |
| 2026-07-01 | Day 2 | 커밋 정리 + 트랙 상세 모달 | FeedView 변경분 커밋, TrackDetailModal half sheet 완성 |
| 2026-07-02 | Day 3 | 네트워크 레이어 | APIClient, Endpoint, HTTPMethod, APIError |
| 2026-07-03 | Day 4 | 인증 기반 | TokenStore, Keychain 저장소, access token 자동 첨부, refresh rotation 구조 |
| 2026-07-04 | Day 5 | 온보딩 — 로그인 연동 | Apple Sign In UI, identityToken 획득, /auth/apple, /genres 조회 |
| 2026-07-05 | Day 6 | 온보딩 — 완료 흐름 | 장르 선택 0~3, /users/me/genres, /users/me/onboarding/complete, 재진입 분기 |
| 2026-07-06 | Day 7 | 피드 API 연동 | GET /feed, cursor 저장/prefetch, hasMore, loading/error state |
| 2026-07-07 | Day 8 | 기본 재생 | AVPlayer 단일 플레이어, pause/resume (sliding window는 후순위) |
| 2026-07-08 | Day 9 | 하입 | POST/DELETE /tracks/{id}/hype optimistic update, listen 이벤트(15초+) |
| 2026-07-09 | Day 10 | 검색 | 검색바, 300ms debounce, /feed/search |
| 2026-07-10 | Day 11 | 마이페이지 기본 | /users/me, /users/me/hypes, 닉네임 변경 shell |
| 2026-07-11 | Day 12 | 설정/세션 | 장르 재설정, 로그아웃, 인증 상태 초기화 |
| 2026-07-12 | Day 13 | 재생 안정화 | 버퍼링/인터럽션/fade 등 AVPlayer 마무리 (여유 있을 때만) |
| 2026-07-13 | Day 14 | 통합 QA | end-to-end 플로우 점검, 시뮬레이터 전체 확인 |
| 2026-07-14 | Day 15 | 안정화 | 크래시 픽스, 네트워크 엣지케이스, 비주얼 폴리시 |
| 2026-07-15 | Day 16 | 마감 빌드 | TestFlight 후보 빌드 |

목표 TestFlight 날짜:

> 2026-07-15

완충 기간:

> 2026-07-16 ~ 2026-07-18

### 압축 일정 운영 원칙

- 매일 시뮬레이터 빌드 성공 상태로 종료
- Figma pixel-perfect보다 동작 가능한 흐름 우선
- 플레이어는 7/15까지 single-player 중심으로 안정화하고, sliding window 정교화는 후순위
- Apple 로그인 설정이 막히면 mock auth로 피드/온보딩 개발을 먼저 진행
- 마이페이지는 “기본 조회/수정/로그아웃”까지만 우선
- 계정 삭제, 세밀한 모션, 인라인 재생은 마감 이후 polish로 분리

---

## 9. 바로 다음 작업

다음 작업은 Phase 1이다.

구체적인 첫 구현 단위:

1. 현재 Xcode 프로젝트 구조 확인
2. `AppRootView` 생성
3. `MainTabView` 생성
4. `FeedView` placeholder 생성
5. `MyPageView` placeholder 생성
6. `DesignSystem` 폴더 생성
7. `DSColor`, `DSTypography`, `DSRadius` 생성
8. 빌드
9. Codex 인앱 시뮬레이터에서 확인

---

## 10. 결정 대기 항목

개발 중 확정이 필요한 항목:

- API base URL에 `/v1` prefix가 실제로 필요한지
- Figma 디자인 토큰의 정확한 hex 값
- 하입 커스텀 SVG asset export 방식
- iTunes attribution 문구 위치
- 약관 / 개인정보처리방침 최종 원문
- Apple Sign In capability 설정 상태

---

## 11. 원칙

- 먼저 골격, 그 다음 실제 기능
- 피드 UI와 플레이어 엔진은 분리
- 네트워크와 인증은 화면에서 직접 호출하지 않음
- cursor는 클라이언트에서 파싱하지 않음
- listen 이벤트는 fire-and-forget
- 하입은 피드에서 optimistic update 허용
- 마이페이지 하입 취소는 optimistic update 금지
- Figma 탭과 시뮬레이터 탭은 사용자가 닫으라고 하기 전까지 닫지 않음

---

## 12. 협업 방식

> **2026-06-30 갱신**: dignify-backend 작업에서 쓰던 "Expert Advisor" 모드를 iOS 개발에도 동일하게 적용하기로 결정. 아래는 그 이전(Codex 혼합형 구현 허용) 방식을 대체한다.

사용자는 SwiftUI를 학습하면서 직접 개발 감각을 쌓고 싶어한다. AI 어시스턴트(Claude/Codex 공통)는 Expert Advisor 역할이며, 직접 코드를 작성하거나 아키텍처를 먼저 제안하지 않는다.

진행 원칙:

- 직접 코드 작성 금지, 아키텍처/구조도 먼저 제안하지 않음 — 사용자가 먼저 방향을 잡는다
- 구현 방법 질문에는 전체 체크리스트 대신 "다음 첫 스텝 + 참고할 클래스/API"만 안내
- 사용자가 코드를 가져오면 도메인 지식 기반으로 검토·피드백(잠재 문제점, trade-off, 더 나은 패턴 제안)
- 작업 전 "왜 이 작업을 하는지"를 짧게 설명
- SwiftUI 개념이 등장하면 짧은 설명을 제공하되, 코드 예시는 사용자가 직접 작성해볼 여지를 남긴다
- 예외: 사용자가 명시적으로 "이건 직접 작성해줘"라고 요청한 보일러플레이트성 코드만 직접 작성 (매번 명시적으로 선택해야 하며 일반 규칙으로 확대되지 않음)
- 테스트는 사용자가 이미 통과 확인 후 리뷰 요청하는 것이므로 직접 실행하지 않고 정적 리뷰만 (단, 에러 메시지를 들고 와서 원인 분석을 요청하면 디버깅 요청이므로 직접 실행/재현)
- 사용자가 작업 중인 파일을 검증 목적으로 임시로 덮어쓰지 않음

권장 작업 루프:

1. 오늘의 목표 1개 정하기
2. 관련 SwiftUI 개념 1~2개 설명
3. 다음 첫 스텝과 참고 키워드/클래스 제시
4. 사용자가 직접 구현
5. 빌드 / 시뮬레이터 확인은 사용자가 진행
6. 사용자가 가져온 코드 리뷰와 다음 태스크 제시

태스크 표기 형식:

```text
목표:
배울 개념:
네가 해볼 것:
완료 기준:
```

---

## 13. 진행 로그

### 2026-06-30

완료한 작업:

- 백엔드 `dignify-backend` README / OpenAPI / 실제 Controller / DTO 기준으로 iOS 연동 계약 확인
- 루트 기획 문서 `01_product_concept.md` ~ `06_db_schema.md`, `figma_make_brief.md`, `legal_notes.md` 확인
- 2026-07-15 마감 기준으로 MVP 일정 재산정
- TCA 미도입 결정 기록
- SwiftUI + Observation + async/await + Service 계층 방향 확정
- 협업 방식 확정: Codex가 전부 구현하지 않고, 사용자 학습용 태스크를 함께 제시
- XcodeBuildMCP로 iOS 프로젝트 빌드/실행 확인
- `serve-sim`으로 Codex 인앱 브라우저에서 iPhone 17 시뮬레이터 미러링 확인
- Figma Make export zip을 디자인 기준 소스로 등록
- App root / Main tab / Onboarding / Feed / MyPage placeholder 골격 추가
- 디자인 시스템 seed 추가:
  - `DSColor`
  - `DSTypography`
  - `DSRadius`
  - `DSButtonStyle`
  - `DSGenreChip`
  - `DSSearchBar`
  - `DSBrandMark`
- 온보딩 화면을 Figma Make export 기준으로 반영
- 장르 선택 화면을 온보딩 내부 placeholder flow로 추가
- SVG 삽 아이콘에서 보라색 단일 심볼 추출
- iOS `AppIcon.appiconset` light / dark / tinted PNG 생성
- `BrandMark.imageset` 생성
- 로그인 / 런치 화면 아이콘을 삽 브랜드 마크로 교체
- 최종 빌드 성공 및 시뮬레이터 화면 확인
- 원본 디자인 zip `/Users/parkjju/Downloads/iOS 앱 디자인 요구사항.zip` 기준으로 `FeedScreen.tsx`, `mockData.ts`, `theme.css`, `HypeIcon.tsx` 확인
- `FeedView` placeholder를 mock 피드 UI로 교체:
  - 검정 배경
  - 원격 아트워크 배경 blur
  - 정사각 아트워크 카드
  - 반투명 검색바 / 최근 검색 패널
  - mock 트랙 데이터
  - 위/아래 스와이프 전환
  - 더블탭 및 버튼 하입 토글
- XcodeBuildMCP로 `iPhone 17` iOS 26.5 Simulator 빌드/실행 성공
- Codex UI automation으로 온보딩 → 장르 선택 → 피드 진입 확인
- Feed 화면 스크린샷 및 스와이프 전환 확인

현재 주요 파일:

- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/App/AppRootView.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/App/AppSession.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/App/MainTabView.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/App/AppTab.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Features/Onboarding/OnboardingFlowView.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Features/Feed/FeedView.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Features/MyPage/MyPageView.swift`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Core/DesignSystem/`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Assets.xcassets/AppIcon.appiconset/`
- `/Users/parkjju/Desktop/toy_project/digging/dignify-iOS/dignify/dignify/Assets.xcassets/BrandMark.imageset/`

다음 채팅에서 시작할 추천 작업:

```text
목표:
TrackDetailModal 원본 디자인을 SwiftUI 하프 모달로 옮긴다.

배울 개념:
sheet(item:), presentationDetents, 하프 모달 레이아웃, track fixture 전달.

네가 해볼 것:
FeedView.swift의 `TrackActionButton(systemName: "opticaldisc")`가 어떤 역할인지 찾고, 버튼을 눌렀을 때 어떤 화면이 떠야 할지 말로 정리한다.

내가 도와줄 것:
원본 `TrackDetailModal.tsx` 기준으로 SwiftUI bottom sheet를 만들고, 현재 mock track 데이터를 연결한다.

완료 기준:
피드에서 디스크 버튼 탭 시 아트워크 / 제목 / 아티스트 / 장르 / 릴리즈 날짜 / 하입 유저 / Apple Music CTA가 있는 하프 모달이 열린다.
```

다음 채팅 첫 메시지 추천:

> `dignify/dignify/docs/dignify_ios_project_memory.md` 읽고 이어서 TrackDetailModal SwiftUI 하프 모달 작업하자.
