import SwiftUI
import SafariServices

/// 약관/개인정보처리방침은 노션 호스팅 페이지를 앱 내 웹뷰(Safari)로 띄운다.
/// 디바이스 언어가 한국어면 국문 페이지, 그 외엔 영문 페이지.
enum LegalDocument: Identifiable {
    case terms
    case privacy

    var id: Self { self }

    var url: URL {
        let ko = Locale.current.language.languageCode?.identifier == "ko"
        let link: String
        switch self {
        case .terms:
            link = ko ? "https://galvanized-borogovia-cd2.notion.site/39234ce1f84d80b88af6f8ba45a6afc7"
                      : "https://galvanized-borogovia-cd2.notion.site/Terms-Conditions-39234ce1f84d805c9ec3edc2fde9ce79"
        case .privacy:
            link = ko ? "https://galvanized-borogovia-cd2.notion.site/39234ce1f84d80889cd2fc918abc6d95"
                      : "https://galvanized-borogovia-cd2.notion.site/Privacy-Policy-39234ce1f84d8079a794c69a4ae74456"
        }
        return URL(string: link)!
    }
}

/// SFSafariViewController를 SwiftUI에서 sheet(item:)로 띄우기 위한 래퍼.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
