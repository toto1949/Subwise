import SwiftUI

struct MainTabView: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection).tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            SubscriptionsView().tabItem { Label("Subs", systemImage: "creditcard.fill") }.tag(1)
            OptimizeView().tabItem { Label("Optimize", systemImage: "sparkles") }.tag(2)
            HouseholdView().tabItem { Label("Family", systemImage: "person.2.fill") }.tag(3)
            AgentView().tabItem { Label("Agent", systemImage: "message.fill") }.tag(4)
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: Int
    @State private var showingProfile = false
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) { case 5..<12: "Good morning"; case 12..<18: "Good afternoon"; default: "Good evening" }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                        Text("Your money,\nsimplified").font(.largeTitle.bold()).fontWidth(.expanded)
                    }
                    SavingsHero(amount: store.availableSavings.compactFormatted, opportunityCount: store.opportunities.count) { selection = 2 }
                    HStack { MetricCard(value: store.monthlySpend.formatted, label: "this month"); MetricCard(value: store.annualSpend.compactFormatted, label: "per year") }
                    HStack { Text("Upcoming").font(.title2.bold()); Spacer(); Button("See all") { selection = 1 }.font(.subheadline.bold()) }
                    if store.isLoading { ProgressView("Loading subscriptions…").frame(maxWidth: .infinity).cardStyle() }
                    else if store.subscriptions.isEmpty { ContentUnavailableView("No subscriptions", systemImage: "creditcard", description: Text("Add one manually or import a trial screenshot.")).cardStyle() }
                    else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.subscriptions.prefix(3).enumerated()), id: \.element.id) { index, subscription in
                                NavigationLink(value: subscription) { SubscriptionRow(subscription: subscription) }.buttonStyle(.plain)
                                if index < min(2, store.subscriptions.count - 1) { Divider().padding(.leading, 60) }
                            }
                        }.cardStyle()
                    }
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green).font(.title2)
                        VStack(alignment: .leading) { Text("\(store.lifetimeVerifiedSavings.compactFormatted) saved with Subwise").font(.headline); Text("Verified lifetime savings").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
                }.padding()
            }
            .premiumScreenBackground()
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingProfile = true } label: { Image(systemName: "person.crop.circle.fill") }.accessibilityLabel("Profile and settings") } }
            .sheet(isPresented: $showingProfile) { SettingsView() }
        }
    }
}

private struct SavingsHero: View {
    let amount: String
    let opportunityCount: Int
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AVAILABLE SAVINGS", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(Theme.mint)
            Text("\(amount)/year").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white)
            Text("\(opportunityCount) \(opportunityCount == 1 ? "opportunity" : "opportunities") found across your subscriptions.").font(.subheadline).foregroundStyle(.white.opacity(0.72))
            Button("Review savings plan", systemImage: "arrow.right", action: action).font(.headline).buttonStyle(.borderedProminent).tint(Theme.green)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.ink, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine).accessibilityAction(named: "Review savings plan", action)
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription
    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName)
            VStack(alignment: .leading, spacing: 3) { Text(subscription.name).font(.headline); Text(subscription.renewalText).font(.caption).foregroundStyle(subscription.status == .trial ? .orange : .secondary) }
            Spacer(); Text(subscription.monthlyCost.formatted).font(.subheadline.bold())
        }.padding(.vertical, 7).accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountSession.self) private var account
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var entitlements = EntitlementStore()
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink { ProfileSettingsView() } label: { Label("Profile", systemImage: "person") }
                    NavigationLink { NotificationSettingsView() } label: { Label("Notifications", systemImage: "bell") }
                    NavigationLink { SavingsGoalSettingsView() } label: { Label("Savings goals", systemImage: "target") }
                }
                Section("Membership") { NavigationLink { PaywallView(store: entitlements) } label: { Label("Subwise Pro", systemImage: "sparkles") } }
                Section("Privacy & Data") {
                    NavigationLink { ConnectedInstitutionsView() } label: { Label("Connected institutions", systemImage: "building.columns") }
                    NavigationLink { AIProcessingSettingsView() } label: { Label("AI processing", systemImage: "sparkles") }
                    NavigationLink { HouseholdSharingSettingsView() } label: { Label("Household sharing", systemImage: "person.2") }
                    NavigationLink { ExportDataView() } label: { Label("Export my data", systemImage: "square.and.arrow.up") }
                }
                Section { Button("Replay onboarding") { hasCompletedOnboarding = false; dismiss() } }
                Section { Button("Sign out", role: .destructive) { Task { await account.signOut(); dismiss() } } }
            }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        }
    }
}
