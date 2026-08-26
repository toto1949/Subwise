import Charts
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
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                        Text("Track less.\nSave more.").font(.largeTitle.bold()).fontWidth(.expanded)
                    }
                    SavingsHero(
                        amount: store.availableSavings.compactFormatted,
                        opportunityCount: store.opportunities.count,
                        progress: savingsRate
                    ) { selection = 2 }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        DashboardMetric(value: store.monthlySpend.formatted, label: "Monthly spend", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        DashboardMetric(value: store.annualSpend.compactFormatted, label: "Annual cost", systemImage: "calendar")
                        DashboardMetric(value: savingsRate.formatted(.percent.precision(.fractionLength(0))), label: "Savings rate", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    if !store.subscriptions.isEmpty {
                        ProjectionChart(monthlySpend: store.monthlySpend, annualSavings: store.availableSavings)
                        MonthlySpendCard(monthlySpend: store.monthlySpend)
                    }
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
            .analyticsScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingProfile = true } label: { Image(systemName: "person.crop.circle.fill") }.accessibilityLabel("Profile and settings") } }
            .sheet(isPresented: $showingProfile) { SettingsView() }
        }
    }

    private var savingsRate: Double {
        guard store.annualSpend.cents > 0 else { return 0 }
        return min(1, Double(store.availableSavings.cents) / Double(store.annualSpend.cents))
    }
}

private struct SavingsHero: View {
    let amount: String
    let opportunityCount: Int
    let progress: Double
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AVAILABLE SAVINGS", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(Theme.mint)
                    Text("\(amount)/year").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.72)
                    Text("\(opportunityCount) \(opportunityCount == 1 ? "opportunity" : "opportunities") across your subscriptions").font(.subheadline).foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                Gauge(value: progress) {
                    Text("Savings rate")
                } currentValueLabel: {
                    Text(progress.formatted(.percent.precision(.fractionLength(0)))).font(.caption.bold()).foregroundStyle(.white)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.sky)
                .frame(width: 72, height: 72)
            }
            Button("Review savings plan", systemImage: "arrow.right", action: action)
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.18), radius: 18, y: 10)
    }
}

private struct DashboardMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.sky)
                .padding(8)
                .background(Theme.sky.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value).font(.title3.bold()).contentTransition(.numericText()).minimumScaleFactor(0.72)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectionPoint: Identifiable {
    let id = UUID()
    let month: Date
    let current: Double
    let optimized: Double
}

private struct ProjectionChart: View {
    let monthlySpend: Money
    let annualSavings: Money

    private var points: [ProjectionPoint] {
        let calendar = Calendar.current
        let monthly = Double(monthlySpend.cents) / 100
        let monthlySavings = Double(annualSavings.cents) / 1200
        return (0..<6).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: .now) else { return nil }
            let multiplier = Double(offset + 1)
            return ProjectionPoint(month: month, current: monthly * multiplier, optimized: max(0, monthly - monthlySavings) * multiplier)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Six-month projection").font(.headline)
                    Text("Current spend compared with your savings plan").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.sky)
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Month", point.month), y: .value("Current", point.current))
                        .foregroundStyle(LinearGradient(colors: [Theme.sky.opacity(0.22), Theme.sky.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Current", point.current),
                        series: .value("Series", "Current")
                    )
                        .foregroundStyle(Theme.sky)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(points) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Optimized", point.optimized),
                        series: .value("Series", "With plan")
                    )
                        .foregroundStyle(Theme.green)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 4]))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine().foregroundStyle(.clear); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine().foregroundStyle(Color(.separator).opacity(0.35)); AxisValueLabel { if let amount = value.as(Double.self) { Text(amount, format: .currency(code: "USD").precision(.fractionLength(0))) } } } }
            .frame(height: 180)
            HStack(spacing: 18) {
                ChartLegendItem(title: "Current", color: Theme.sky)
                ChartLegendItem(title: "With plan", color: Theme.green)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Six month spend projection")
    }
}

private struct MonthlySpendCard: View {
    let monthlySpend: Money
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Monthly spend", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.headline).foregroundStyle(Theme.sky)
            Text(monthlySpend.formatted).font(.largeTitle.bold())
            Text("Your recurring subscription total")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monthly spend \(monthlySpend.formatted)")
    }
}

private struct ChartLegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        Label {
            Text(title).font(.caption).foregroundStyle(.secondary)
        } icon: {
            Capsule().fill(color).frame(width: 18, height: 4)
        }
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription
    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(symbol: subscription.symbol, colorName: subscription.colorName, serviceName: subscription.name)
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
