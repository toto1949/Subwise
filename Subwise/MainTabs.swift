import Charts
import SwiftUI

struct MainTabView: View {
    @Binding private var pendingHouseholdInviteToken: String?
    @State private var selection = 0
    @State private var selectedCategory: SubscriptionCategory?
    init(pendingHouseholdInviteToken: Binding<String?> = .constant(nil)) {
        _pendingHouseholdInviteToken = pendingHouseholdInviteToken
    }
    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection, selectedCategory: $selectedCategory).tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            SubscriptionsView(category: $selectedCategory).tabItem { Label("Subs", systemImage: "creditcard.fill") }.tag(1)
            OptimizeView().tabItem { Label("Optimize", systemImage: "sparkles") }.tag(2)
            HouseholdView(pendingInviteToken: $pendingHouseholdInviteToken).tabItem { Label("Family", systemImage: "person.2.fill") }.tag(3)
            AgentView().tabItem { Label("Agent", systemImage: "message.fill") }.tag(4)
        }
        .onChange(of: pendingHouseholdInviteToken) { _, token in
            if token != nil { selection = 3 }
        }
    }
}

private extension View {
    @ViewBuilder
    func dashboardEntrance(_ hasAppeared: Bool, index: Int, reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 18)
                .scaleEffect(hasAppeared ? 1 : 0.98)
                .animation(.spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.055), value: hasAppeared)
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: Int
    @Binding var selectedCategory: SubscriptionCategory?
    @State private var showingProfile = false
    @State private var showingDiscovery = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    if store.activeSubscriptions.isEmpty && !store.isLoading {
                        FindSubscriptionsHero { showingDiscovery = true }
                            .dashboardEntrance(hasAppeared, index: 0, reduceMotion: reduceMotion)
                    } else {
                        SavingsHero(
                            amount: store.availableSavings.compactFormatted,
                            opportunityCount: store.opportunities.count,
                            progress: savingsRate
                        ) { selection = 2 }
                        .dashboardEntrance(hasAppeared, index: 0, reduceMotion: reduceMotion)
                    }
                    if let trial = store.activeSubscriptions.first(where: { $0.status == .trial }) {
                        DashboardAlertCard(subscription: trial) { selection = 1 }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        DashboardMetric(value: store.monthlySpend.formatted, label: "Monthly spend", systemImage: "arrow.triangle.2.circlepath.circle.fill") { selection = 1 }
                            .dashboardEntrance(hasAppeared, index: 1, reduceMotion: reduceMotion)
                        DashboardMetric(value: store.annualSpend.compactFormatted, label: "Annual cost", systemImage: "calendar") { selection = 1 }
                            .dashboardEntrance(hasAppeared, index: 2, reduceMotion: reduceMotion)
                        DashboardMetric(value: savingsRate.formatted(.percent.precision(.fractionLength(0))), label: "Savings rate", systemImage: "chart.line.uptrend.xyaxis") { selection = 2 }
                            .dashboardEntrance(hasAppeared, index: 3, reduceMotion: reduceMotion)
                    }
                    .redacted(reason: store.isLoading ? .placeholder : [])
                    if !store.activeSubscriptions.isEmpty {
                        CategorySpendCard(subscriptions: store.activeSubscriptions) { category in
                            selectedCategory = category
                            selection = 1
                        }
                        .dashboardEntrance(hasAppeared, index: 4, reduceMotion: reduceMotion)
                        ProjectionChart(monthlySpend: store.monthlySpend, annualSavings: store.availableSavings)
                            .dashboardEntrance(hasAppeared, index: 5, reduceMotion: reduceMotion)
                        MonthlySpendCard(monthlySpend: store.monthlySpend)
                            .dashboardEntrance(hasAppeared, index: 6, reduceMotion: reduceMotion)
                    }
                    HStack { Text("Upcoming").font(.title2.bold()); Spacer(); Button("See all") { selection = 1 }.font(.subheadline.bold()) }
                    if store.isLoading { DashboardSkeleton() }
                    else if store.activeSubscriptions.isEmpty { ContentUnavailableView("Ready to scan", systemImage: "sparkle.magnifyingglass", description: Text("Connect a source once and review detected subscriptions before anything is added.")).cardStyle() }
                    else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.upcomingSubscriptions.prefix(3).enumerated()), id: \.element.id) { index, subscription in
                                NavigationLink(value: subscription) { SubscriptionRow(subscription: subscription) }.buttonStyle(.plain)
                                if index < min(2, store.activeSubscriptions.count - 1) { Divider().padding(.leading, 60) }
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
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion { hasAppeared = true }
                else { withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) { hasAppeared = true } }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Subscription.self) { SubscriptionDetailView(subscription: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingDiscovery = true } label: { Image(systemName: "sparkle.magnifyingglass") }.accessibilityLabel("Find subscriptions")
                    Button { showingProfile = true } label: { Image(systemName: "person.crop.circle.fill") }.accessibilityLabel("Profile and settings")
                }
            }
            .sheet(isPresented: $showingProfile) { SettingsView() }
            .sheet(isPresented: $showingDiscovery) { SubscriptionDiscoveryView() }
        }
    }

    private var savingsRate: Double {
        guard store.annualSpend.cents > 0 else { return 0 }
        return min(1, Double(store.availableSavings.cents) / Double(store.annualSpend.cents))
    }
}

private struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 12) { Circle().fill(Color.secondary.opacity(0.18)).frame(width: 44, height: 44); VStack(alignment: .leading, spacing: 6) { Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 130, height: 13); Capsule().fill(Color.secondary.opacity(0.12)).frame(width: 90, height: 10) }; Spacer(); Capsule().fill(Color.secondary.opacity(0.15)).frame(width: 55, height: 14) }.padding(.vertical, 8)
                if index < 2 { Divider().padding(.leading, 56) }
            }
        }.cardStyle().accessibilityLabel("Loading upcoming subscriptions")
    }
}

private struct FindSubscriptionsHero: View {
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("SUBSCRIPTION DISCOVERY", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Theme.mint)
            Text("Find what you’re paying for.").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Connect a bank, Apple Wallet, or a screenshot. Most users can review results in under a minute.").foregroundStyle(.white.opacity(0.76))
            Button("Find my subscriptions", systemImage: "arrow.right", action: action).font(.headline).buttonStyle(.borderedProminent).tint(Theme.green)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct DashboardAlertCard: View {
    let subscription: Subscription
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) { Text("Free trial ends soon").font(.headline); Text("\(subscription.name) • \(subscription.nextPaymentText)").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Text("Remind me").font(.caption.bold()).foregroundStyle(Theme.green)
            }.cardStyle()
        }.buttonStyle(.plain)
    }
}

private struct CategorySpendSlice: Identifiable {
    let category: SubscriptionCategory
    let cents: Int
    let subscriptionCount: Int
    var id: SubscriptionCategory { category }
}

private struct CategorySpendCard: View {
    let subscriptions: [Subscription]
    let action: (SubscriptionCategory) -> Void

    private var slices: [CategorySpendSlice] {
        Dictionary(grouping: subscriptions, by: \.category)
            .map { category, items in
                CategorySpendSlice(category: category, cents: items.reduce(0) { $0 + $1.monthlyCost.cents }, subscriptionCount: items.count)
            }
            .sorted { $0.cents > $1.cents }
    }

    private var totalCents: Int { slices.reduce(0) { $0 + $1.cents } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spend by category").font(.headline)
                    Text("Tap a category to review its subscriptions").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.pie.fill").foregroundStyle(Theme.sky)
            }
            VStack(spacing: 16) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Monthly spend", slice.cents),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .cornerRadius(4)
                    .foregroundStyle(slice.category.chartColor)
                }
                .chartLegend(.hidden)
                .chartBackground { _ in
                    VStack(spacing: 1) {
                        Text(Money(cents: totalCents).compactFormatted).font(.headline)
                        Text("per month").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(slices) { slice in
                        Button { action(slice.category) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(slice.category.chartColor).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slice.category.rawValue).font(.caption.bold()).lineLimit(1)
                                    Text("\(slice.subscriptionCount) • \(percentage(for: slice))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(slice.category.chartColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(slice.category.rawValue), \(percentage(for: slice)), \(slice.subscriptionCount) subscriptions")
                        .accessibilityHint("Shows this category")
                    }
                }
            }
        }
        .cardStyle()
    }

    private func percentage(for slice: CategorySpendSlice) -> String {
        guard totalCents > 0 else { return "0%" }
        return (Double(slice.cents) / Double(totalCents)).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct SavingsHero: View {
    let amount: String
    let opportunityCount: Int
    let progress: Double
    let action: () -> Void
    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AVAILABLE SAVINGS", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(Theme.mint)
                    Text("\(amount)/year").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.72)
                    Text("\(opportunityCount) \(opportunityCount == 1 ? "opportunity" : "opportunities") across your subscriptions").font(.subheadline).foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                Gauge(value: animatedProgress) {
                    Text("Savings rate")
                } currentValueLabel: {
                    Text(animatedProgress.formatted(.percent.precision(.fractionLength(0)))).font(.caption.bold()).foregroundStyle(.white)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.sky)
                .frame(width: 72, height: 72)
                .shadow(color: Theme.sky.opacity(0.35), radius: 10)
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
        .onAppear {
            guard animatedProgress != progress else { return }
            if reduceMotion { animatedProgress = progress }
            else { withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) { animatedProgress = progress } }
        }
        .onChange(of: progress) { _, newValue in
            if reduceMotion { animatedProgress = newValue }
            else { withAnimation(.spring(response: 0.6, dampingFraction: 0.84)) { animatedProgress = newValue } }
        }
    }
}

private struct DashboardMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(Theme.sky)
                    .padding(8)
                    .background(
                        LinearGradient(colors: [Theme.sky.opacity(0.24), Theme.sky.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .shadow(color: Theme.sky.opacity(0.18), radius: 8, y: 4)
                Text(value).font(.title3.bold()).contentTransition(.numericText()).minimumScaleFactor(0.72)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens related Subwise data")
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
    @State private var chartProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .chartPlotStyle { plot in plot.opacity(chartProgress).scaleEffect(chartProgress, anchor: .leading) }
            .frame(height: 180)
            HStack(spacing: 18) {
                ChartLegendItem(title: "Current", color: Theme.sky)
                ChartLegendItem(title: "With plan", color: Theme.green)
            }
        }
        .cardStyle()
        .onAppear {
            guard chartProgress < 1 else { return }
            if reduceMotion { chartProgress = 1 }
            else { withAnimation(.easeOut(duration: 0.85)) { chartProgress = 1 } }
        }
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
                    Link(destination: URL(string: "https://subwise-api.vercel.app/privacy-policy")!) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                }
                Section { Button("Replay onboarding") { hasCompletedOnboarding = false; dismiss() } }
                Section { Button("Sign out", role: .destructive) { Task { await account.signOut(); dismiss() } } }
            }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
        }
    }
}
