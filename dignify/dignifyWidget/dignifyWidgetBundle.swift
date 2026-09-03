import SwiftUI
import WidgetKit

/// 홈스크린 위젯과 제어센터 컨트롤은 안 만든다 — WidgetKit은 소리를 못 내고,
/// 딥링크 런처는 홈스크린 아이콘 대비 얻는 게 없다. 여기 있는 건 Live Activity 하나뿐이다.
@main
struct dignifyWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiggingLiveActivity()
    }
}
