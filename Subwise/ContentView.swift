import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var store = AppStore()
    @State private var account = AccountSession()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                switch account.state {
                case .authenticated, .development, .offline:
                    MainTabView().environment(store).environment(account)
                case .checking:
                    ProgressView("Checking your session…")
                default:
                    SignInView().environment(account)
                }
            } else {
                OnboardingFlow { hasCompletedOnboarding = true }
            }
        }
        .tint(Theme.green)
    }
}

#Preview("App") { ContentView() }
#Preview("Dashboard") { MainTabView().environment(AppStore()).environment(AccountSession()) }
