import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var store = AppStore()
    @State private var account = AccountSession()
    @State private var pendingHouseholdInviteToken: String?

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                switch account.state {
                case .authenticated, .development, .offline:
                    MainTabView(pendingHouseholdInviteToken: $pendingHouseholdInviteToken).environment(store).environment(account)
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
        .onOpenURL { url in
            guard url.host == "subwise-api.vercel.app" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 3, parts[0] == "household", parts[1] == "invite", parts[2].count < 500 else { return }
            pendingHouseholdInviteToken = parts[2]
        }
    }
}

#Preview("App") { ContentView() }
#Preview("Dashboard") { MainTabView().environment(AppStore()).environment(AccountSession()) }
