import ActivityKit
import AppIntents
import Foundation

/// 백그라운드 디깅 중 잠금화면에 띄우는 Live Activity.
///
/// **잠금화면 Now Playing이 이미 아트워크·곡 정보·다음/이전을 그린다.** 그걸 또 그리면
/// 같은 정보가 두 번 쌓일 뿐이다. 여기 있을 이유는 Now Playing에 **없는** 것 하나,
/// 하입뿐이다 — 그게 없으면 이 Activity는 만들 이유가 없다.
///
/// 아트워크를 넣지 않은 것도 그래서다. Live Activity 뷰는 네트워크를 못 타서 이미지를
/// 띄우려면 App Group 컨테이너에 파일로 떨궈야 하는데, 바로 위에 이미 같은 아트워크가 떠 있다.
struct DiggingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackId: Int
        var trackName: String
        var artistName: String
        var isHyped: Bool
    }
}

/// 앱 프로세스의 하입 로직을 Live Activity 버튼에 연결하는 지점.
///
/// 이 파일은 위젯 익스텐션 타깃에도 들어가지만 거기서는 `toggleHype`이 nil로 남는다.
/// `LiveActivityIntent`는 **앱 프로세스에서 실행되기 때문에** 그래도 된다 — 덕분에
/// 토큰도 API 클라이언트도 익스텐션과 공유할 필요가 없다(Keychain Access Group 불필요).
@MainActor
enum HypeIntentBridge {
    static var toggleHype: ((Int) -> Void)?
}

/// 잠금화면 Live Activity의 하입 버튼.
/// 낙관적 갱신·롤백·계측·시드 재구성은 전부 앱 쪽 `setHype`이 그대로 처리한다.
struct ToggleHypeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Hype"

    @Parameter(title: "Track")
    var trackId: Int

    init() {}
    init(trackId: Int) { self.trackId = trackId }

    @MainActor
    func perform() async throws -> some IntentResult {
        HypeIntentBridge.toggleHype?(trackId)
        return .result()
    }
}
