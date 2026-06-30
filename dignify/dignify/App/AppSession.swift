import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    var authState: AuthState = .unknown

    func resolveInitialState() {
        authState = .signedOut
    }
}

enum AuthState {
    case unknown
    case signedOut
    case onboardingRequired
    case signedIn
}
