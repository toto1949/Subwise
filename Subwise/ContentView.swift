import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var store = AppStore()
    @State private var account = AccountSession()
    @State private var pendingHouseholdInviteToken: String?

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestWallet") {
                NavigationStack { WalletView() }.environment(store).environment(account)
            } else { appContent }
            #else
            appContent
            #endif
        }
        .tint(Theme.green)
        .onOpenURL { url in
            guard url.host == "subwise-api.vercel.app" else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 3, parts[0] == "household", parts[1] == "invite", parts[2].count < 500 else { return }
            pendingHouseholdInviteToken = parts[2]
        }
    }
    @ViewBuilder private var appContent: some View {
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
}

#Preview("App") { ContentView() }
#Preview("Dashboard") { MainTabView().environment(AppStore()).environment(AccountSession()) }
