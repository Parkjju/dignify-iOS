import XCTest

/// 게스트 경로 통합 테스트. Apple 로그인은 자동화할 수 없어서(시스템 시트 + 실제 계정)
/// 로그인 없이 갈 수 있는 데까지가 UI 테스트의 실제 사정거리다.
/// 여기서 잡는 것: 앱이 뜨는가 · 게스트로 들어가지는가 · 계정 기능이 로그인 게이트에 막히는가.
/// 셋 다 회귀하면 앱이 통째로 못 쓰게 되는 경로라 값이 있다.
final class GuestFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 문구로 요소를 찾으므로 기기 언어와 무관하게 영어로 고정한다.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// 로그인 상태로 남은 시뮬레이터에선 웰컴 화면이 아예 안 뜬다 —
    /// 실패로 찍으면 원인을 엉뚱한 데서 찾게 되므로 명시적으로 건너뛴다.
    private func enterGuest(_ app: XCUIApplication) throws {
        let browse = app.buttons["Browse without signing in"]
        guard browse.waitForExistence(timeout: 20) else {
            throw XCTSkip("웰컴 화면이 없다 — 이미 로그인된 시뮬레이터. 로그아웃하거나 앱을 지우고 다시 돌릴 것.")
        }
        browse.tap()
    }

    func testGuestReachesTheFeedTabs() throws {
        let app = launchApp()
        try enterGuest(app)

        // 탭바가 뜨면 게스트 진입 성공(피드 콘텐츠는 서버에 의존하므로 여기선 안 본다).
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Picks"].exists)
        XCTAssertTrue(app.tabBars.buttons["My"].exists)
    }

    /// 게스트에게 마이페이지 본문이 보이면 401이 줄줄 나고 빈 화면이 뜬다.
    /// 로그인 유도 화면으로 갈아치우는 분기가 살아 있는지 본다.
    func testGuestMyPageIsGatedBehindSignIn() throws {
        let app = launchApp()
        try enterGuest(app)

        XCTAssertTrue(app.tabBars.buttons["My"].waitForExistence(timeout: 10))
        app.tabBars.buttons["My"].tap()

        XCTAssertTrue(app.staticTexts["Build your own taste"].waitForExistence(timeout: 5))

        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.exists)
        signIn.tap()

        // 게이트 시트는 로그인 전용 — 여기서 다시 게스트로 빠질 수 있으면 게이트가 아니다.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Browse without signing in"].exists)

        cancel.tap()
        XCTAssertTrue(app.staticTexts["Build your own taste"].waitForExistence(timeout: 5))
    }
}
